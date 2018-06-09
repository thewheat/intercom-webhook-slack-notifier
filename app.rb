require 'sinatra'
require 'intercom'
require 'dotenv'
require 'sanitize'
require "reverse_markdown"
require 'open-uri'
require 'slack-notifier'
require 'httparty'

Dotenv.load

post '/' do
  request.body.rewind
  payload_body = request.body.read

  puts "== Intercom Webhook payload ==================================="
  puts payload_body
  puts "==============================================================="
  begin
    data = JSON.parse(payload_body)
    verify_signature(payload_body)
    puts "Topic Recieved: #{data['topic']}"
    process_webhook(data)
  rescue => e
    puts "Payload not JSON formatted"
    puts e.inspect
    puts e.backtrace
  end
end

def listening_on_webhook(topic)
  notifications_wanted = ENV["NOTIFICATIONS_WANTED"]
  return !notifications_wanted.index(topic).nil?
end

def process_webhook(data)
  notifications_wanted = ENV["NOTIFICATIONS_WANTED"]
  topic = data["topic"]
  if notifications_wanted.index(topic).nil?
    puts "Ignoring as not on wanted list of #{notifications_wanted}"
  else 
    process_slack_notification_webhook(data)
  end
end


def verify_signature(payload_body)
  secret = "secret"
  expected = request.env['HTTP_X_HUB_SIGNATURE']
  if expected.nil? || expected.empty? then
    puts "Not signed. Not calculating"
  else
    signature = 'sha1=' + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha1'), secret, payload_body)
    puts "Expected  : #{expected}"
    puts "Calculated: #{signature}"
    if Rack::Utils.secure_compare(signature, expected) then
      puts "   Match"
    else
      puts "   MISMATCH!!!!!!!"
      return halt 500, "Signatures didn't match!"
    end
  end
end


def get_environment_boolean_value(name, default_value)
  value = ENV[name]
  return default_value if value.nil?
  value = value.to_s.downcase
  return true if ( value == "1" || value == "true" || value == "yes")
  return false if ( value == "0" || value == "false" || value == "no")
  return default_value
end

################################################################ 
# Formatting

def format_user_display_name(user)
  "#{user['name'] || user['user_id'] || ['user.email']} (#{user['type']})"
end

def get_color (reply_type)
    if reply_type[:user_reply]
      return "#EEEEEE"
    elsif reply_type[:opened]
      return "#D83D34"
    elsif reply_type[:closed]
      return "#53AD60"
    elsif reply_type[:assignment]
      return "#B0A5E8"
    elsif reply_type[:note]
      return "#FBE3B9"
    else
      return "#E9F0FE"
    end
end

def get_emoji(reply_type)
    if reply_type[:user_reply]
      return ":envelope_with_arrow:"
    elsif reply_type[:opened]
      return ":arrow_heading_up:"
    elsif reply_type[:closed]
      return ":white_check_mark:"
    elsif reply_type[:assignment]
      return ":clipboard:"
    elsif reply_type[:note]
      return ":key:"
    else
      return ":speech_balloon:"
    end
end

################################################################ 
# Formatting

def process_slack_notification_webhook(raw_data)
  user_reply = (raw_data["topic"] == "conversation.user.replied" )
  new_message = (raw_data["topic"] == "conversation.user.created" || raw_data["topic"] == "conversation.admin.single.created")
  app_id = raw_data["app_id"];
  data = raw_data["data"]
  conversation = data["item"]
  current_assignee = data["item"]["assignee"]
  user = data["item"]["user"]
  message = data["item"]["conversation_message"]
  part = data["item"]["conversation_parts"]["conversation_parts"][0] if data["item"]["conversation_parts"] && data["item"]["conversation_parts"]["conversation_parts"]
  if part
    admin = part["author"] 
    opened = part["part_type"] == "open"
    closed = part["part_type"] == "close"
    note = part["part_type"] == "note"
    assignment = part["part_type"] == "assignment"
    away_mode_assignment = part["part_type"] == "away_mode_assignment"
    assignee = part["assigned_to"]
  end
  admin = current_assignee if new_message && !user_reply
  link_to_convo = data["item"]["links"]["conversation_web"]
  user_link = "https://app.intercom.io/apps/#{app_id}/users/#{user['id']}"

  if new_message
    incoming_message_source = message
  else
    incoming_message_source = part
  end

  output_contents=""
  raw_incoming_message = incoming_message_source['body']

  if should_skip(raw_data["topic"], raw_incoming_message)
    puts "Skipping this #{raw_data["topic"]} because we are listening on it elsewhere"
    return
  end

  # convert HTML message from Intercom to Markdown
  raw_markdown = ReverseMarkdown.convert(raw_incoming_message).gsub(/!\[\]\((.*)\)/,"\\1")
  slack_markdown = Slack::Notifier::Util::LinkFormatter.format(raw_markdown).gsub(/&nbsp;/," ")
  output_contents = "#{slack_markdown}\n" if incoming_message_source["body"]
  if incoming_message_source["attachments"].count > 0
    attachments = incoming_message_source['attachments'].map{|a|
      "<#{a['url']}|#{a['name']}>"
    }.join("\n")
  end

  if user_reply
    if new_message
      text = "started"
    else
      text = "replied to"
    end
    output_title  = "<#{user_link}|#{format_user_display_name(user)}> #{text} <#{link_to_convo}|conversation (#{conversation['id']})>"
  else
    text = "replied to"
    text = "added a note to" if note
    text = "closed" if closed
    text = "opened" if opened
    text = "assigned" if assignment
    text = "created new" if new_message
    text = "away mode reassigned" if away_mode_assignment

    if assignee
      assignee_text = " and assigned to"
      assignee_text = " to" if assignee && (assignment || away_mode_assignment)

      if assignee["type"] == "nobody_admin"
        assigned_name = "Nobody / Unassigned"
      else
        assigned_name = "#{assignee['name']}"
        assigned_name = "themselves" if admin['id'] == assignee['id']
        link_to_assigned = "https://app.intercom.io/a/apps/#{app_id}/admins/#{assignee['id']}"
        assigned_name = "<#{link_to_assigned}|#{assigned_name}>"        
      end
      assignee_text = "#{assignee_text} #{assigned_name}"
    end

    admin_text = "Unknown admin"    
    if admin
      link_to_admin = "https://app.intercom.io/a/apps/#{app_id}/admins/#{admin['id']}"
      admin_text = "<#{link_to_admin}|#{admin['name']}>"
    end

    conversation_details = ""
    conversation_details = " with <#{user_link}|#{format_user_display_name(user)}>" if user

    output_title = "#{admin_text} #{text} <#{link_to_convo}|conversation (#{conversation['id']})>#{conversation_details}#{assignee_text}"
  end
  convo_id = conversation["id"];

  response = post_to_slack(output_title, {
    body: output_contents,
    attachments: attachments,
    reply_type: {
      user_reply: user_reply,
      note: note,
      closed: closed,
      opened: opened,
      assignment: assignment,
      new_message: new_message,
    }
  })
end


# If listening on multiple webhooks there can be scenarios with multiple webhooks
# Logic below is used to skip webhooks if it is being processed elsewhere
# 3 scenarios where multiple webbhoks come
# --------------------------------------------------------
#  Conversation in unassigned: admin replies and closes 
#   - conversation.admin.replied
#   - conversation.admin.closed
#   - conversation.admin.assigned
# --------------------------------------------------------
#  Conversation in unassigned: admin replies
#   - conversation.admin.replied
#   - conversation.admin.assigned
# --------------------------------------------------------
#  Conversation in assigned: admin replies and closes
#   - conversation.admin.replied
#   - conversation.admin.closed
# --------------------------------------------------------
# Prioritising  "conversation.admin.replied" works. 

def should_skip(topic, has_reply)
  return true if topic == "conversation.admin.closed" && has_reply && listening_on_webhook("conversation.admin.replied")
  return true if topic == "conversation.admin.assigned" && has_reply && listening_on_webhook("conversation.admin.replied")
  return false
end



def post_to_slack (title, data)
  use_attachment_display = get_environment_boolean_value("SLACK_DISPLAY_USE_ATTACHMENTS", false)
  show_contents = get_environment_boolean_value("SLACK_DISPLAY_SHOW_CONTENTS", false)
  
  options = {
    headers: {"Content-Type" => "application/x-www-form-urlencoded"},
    body: {
      token: ENV["SLACK_TOKEN"],
      channel: ENV["SLACK_CHANNEL"],
      unfurl_media: true
    }
  }

  output_string = "#{get_emoji(data[:reply_type])} #{title}"
  output_string = "#{output_string}\n#{data[:body]}" if show_contents

  if use_attachment_display then
    options[:body][:attachments] = [] if options[:body][:attachments].nil? 
    options[:body][:attachments] << {
      color: get_color(data[:reply_type]),
      text: output_string
    }
  else
    options[:body][:text] = output_string
  end

  if show_contents then
    if data[:attachments]
      options[:body][:attachments] = [] if options[:body][:attachments].nil? 
      options[:body][:attachments] << {
        color: "#F35A00",
        fields: [
            {
                title: "Attachments",
                value: data[:attachments]
            }
        ]
      }
    end
  end

  options[:body][:attachments] = options[:body][:attachments].to_json if options[:body] && options[:body][:attachments] 
  HTTParty.post('https://slack.com/api/chat.postMessage', options)
  
  200
end

