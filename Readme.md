# Intercom Webhook Slack Notifier
- This is [Intercom webhook](https://docs.intercom.io/integrations/webhooks) processing code to 
   - send notifications to Slack


**Attachments with no contents**

![](/docs/Preview_Attachments_No_Content.png)

**Attachments with show contents** (images do not unfurl / expand inline)

![](/docs/Preview_Attachments_Show_Content.png)

**No Attachments with show contents** (images will unfurl / expand inline)

![](/docs/Preview_No_Attachments_Show_Content.png)


## Setup - Environment Variable Configuration
- lists all variables needed for this script to work
- `SLACK_TOKEN`
	- A standard access token should be fine here
	- Apply for an access token  https://app.intercom.io/developers/_
	- Read more about access tokens https://developers.intercom.com/reference#personal-access-tokens-1 
- `SLACK_CHANNEL`
	- the ID of Slack channel you wish to post notifications to
- `NOTIFICATIONS_WANTED`
    - the names of the webhooks the Intercom webhooks you wish to send to Intercom
    - separate the names by commas
    - current supports the following: conversation.user.created,conversation.user.replied,conversation.admin.replied,conversation.admin.assigned,conversation.admin.noted,conversation.admin.closed,conversation.admin.opened)
- `SLACK_DISPLAY_SHOW_CONTENTS`
    - set to true / 1 if you want to show the context of the messages in Slack
- `SLACK_DISPLAY_USE_ATTACHMENTS`
    - set to true / 1 if you want to Slack's attachments which allows setting a color on the side to indicate the type of reply but you will lose the ability to unfurl / expand images sent and received (this is only applicable if you enable SLACK_DISPLAY_SHOW_CONTENTS)
- For development just rename `.env.sample` to `.env` and modify values appropriately
- Install [tnef](https://github.com/verdammelt/tnef) on server that will run the webhook code


### Setup in Slack 

#### Create the App and Install it 
- Go to https://api.slack.com/apps/
- Create Slack App
![](/docs/1.%20Create%20Slack%20App.png) 
- Specify App Name
![](/docs/2.%20App%20Name.png) 
- Go to "Oauth and permissions page"
![](/docs/3.%20Oauth%20and%20permissions%20page.png) 
- And add Scope: Send messages as YOUR_SLACK_APP_NAME / `chat:write:bot`
![](/docs/4.%20Add%20Scope.png) 
- Install App
![](/docs/5.%20Install%20App.png) 
- Get the OAuth Access Token 
![](/docs/6.%20Tokens.png) 

#### Getting Channel ID
- Go to Slack 
- Right click channel
- Copy Link
- Paste link and extract channel ID which is the last part of the link

![](/docs/7.%20Channel%20ID.png) 

## Running this locally
```
gem install bundler # install bundler
bundle install      # install dependencies
ruby app.rb         # run the code
ngrok http 4567     # uses https://ngrok.com/ to give you a public URL to your local code to process the webhooks
```

- Create a new webhook in the [Intercom Developer Hub](https://app.intercom.io/developers/_) > Webhooks page
- Listen any on the following notification: 
   - "New message from a user or lead" / `conversation.user.created`
   - "Reply from a user or lead" / `conversation.user.replied` 
   - "Reply from your teammates" / `conversation.admin.replied`   
   - "Conversation assigned to any teammate" / `conversation.admin.assigned`
   - "Note added to a conversation" / `conversation.admin.noted`
   - "Conversation closed" / `conversation.admin.closed`
   - "Conversation opened" / `conversation.admin.opened`
- In webhook URL specify the ngrok URL

