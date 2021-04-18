#!/bin/bash                           

function post_to_slack () {  
        # format message as a code block ```${msg}``` 
        SLACK_MESSAGE="\`\`\`$1\`\`\`"
        SLACK_URL=SLACK_HOOK_URL
        case "$2" in
                INFO)
                        SLACK_ICON=':slack:'
                        ;;
                WARNING)
                        SLACK_ICON=':warning:'
                        ;;
                ERROR)
                        SLACK_ICON=':bangbang:'
                        ;;
                *)
                        SLACK_ICON=':slack:'
                        ;;
        esac

        curl -X POST --data "payload={\"text\": \"${SLACK_ICON} ${SLACK_MESSAGE}\", \"username\": \"login-bot\"}" ${SLACK_URL}
}

USER="User:        $PAM_USER"         
REMOTE="Remote host: $PAM_RHOST"      
SERVICE="Service:     $PAM_SERVICE"   
TTY="TTY:         $PAM_TTY"           
DATE="Date:        `date`"
LOGINMESSAGE="$PAM_SERVICE login for account $PAM_USER"
SERVER="Server:      server.domain.com"
if [ "$PAM_TYPE" = "open_session" ]
then
        post_to_slack "${LOGINMESSAGE}\n\n${SERVER}\n${USER}\n${REMOTE}\n${SERVICE}\n${TTY}\n${DATE}" "INFO"
fi
exit 0