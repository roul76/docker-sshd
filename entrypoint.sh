#!/bin/sh
set -o pipefail

# Limit incoming traffic to SSH_SUBNET on port SSHD_PORT
[ "${SSH_SUBNET}" != "" -a "${SSHD_PORT}" != "" ] && \
  iptables -A INPUT -s "${SSH_SUBNET}" -p tcp --dport "${SSHD_PORT}" -j ACCEPT && \
  iptables -A OUTPUT -d "${SSH_SUBNET}" -p tcp --sport "${SSHD_PORT}" -m state --state ESTABLISHED -j ACCEPT

# Set IPv4 nameservers if provided
[ "${SSH_NAMESERVERS}" != "" ] && \
  echo "${SSH_NAMESERVERS}"|sed 's/|/\n/g'|while read n; do
    echo "nameserver ${n}" >> /etc/resolv.conf
    iptables -A OUTPUT -p udp -d "${n}/32" --dport 53 -m state --state NEW,ESTABLISHED -j ACCEPT
    iptables -A INPUT  -p udp -s "${n}/32" --sport 53 -m state --state ESTABLISHED -j ACCEPT
    iptables -A OUTPUT -p tcp -d "${n}/32" --dport 53 -m state --state NEW,ESTABLISHED -j ACCEPT
    iptables -A INPUT  -p tcp -s "${n}/32" --sport 53 -m state --state ESTABLISHED -j ACCEPT
  done

# Allow access to certain networks listed in SSH_ACCESSIBLE_NETWORKS
[ "${SSH_ACCESSIBLE_NETWORKS}" != "" ] && \
  echo "${SSH_ACCESSIBLE_NETWORKS}"|sed 's/|/\n/g'|while read n; do
    iptables -A OUTPUT -d "${n}" -j ACCEPT
    iptables -A INPUT -s "${n}" -m state --state ESTABLISHED -j ACCEPT
  done

# Apply DROP policies to any other network traffic
iptables -P OUTPUT DROP
iptables -P INPUT DROP
iptables -P FORWARD DROP

# Create login user
[ "${SSH_USER_ID}" = "" ] && SSH_USER_ID=1001
[ "${SSH_USER}" != "" -a "${SSH_HASH}" != "" ] && \
  addgroup -g "${SSH_USER_ID}" webconsole && \
  adduser -u "${SSH_USER_ID}" -G webconsole -S -h /home/"${SSH_USER}" -s "/bin/zsh" "${SSH_USER}" && \
  echo "${SSH_USER}:${SSH_HASH}"|chpasswd -e && \
  touch "/home/${SSH_USER}/.zshrc" && \
  chown "${SSH_USER}" "/home/${SSH_USER}/.zshrc" && \
  chmod 640 "/home/${SSH_USER}/.zshrc" && \
  echo '
HISTFILE=~/.histfile
HISTSIZE=10000
SAVEHIST=10000
bindkey -e
zstyle :compinstall filename '"'"'/home/'"${SSH_USER}"'/.zshrc'"'"'
autoload -Uz compinit && compinit
autoload -U colors && colors
PROMPT="%{$fg[blue]%}%D %T%{$reset_color%} %{$fg[yellow]%}%B%d%b%{$reset_color%}
$ "
alias ls='"'"'ls --color'"'"'
alias l='"'"'ls -lah'"'"'
alias la='"'"'ls -lAh'"'"'
alias ll='"'"'ls -lh'"'"'
alias lsa='"'"'ls -lah'"'"'
alias md='"'"'mkdir -p'"'"'
alias rd='"'"'rmdir'"'"'
'>>"/home/${SSH_USER}/.zshrc"

# Create SSH keys
[ "$(find "${SSH_KEY_DIRECTORY}/" -name "*.key*" -type f 2>/dev/null)" != "" ] && \
  echo "echo "'"'"
*** SSH key files stored in ${SSH_KEY_DIRECTORY} ***
"'"'>>"/home/${SSH_USER}/.zshrc"

# Retrieve own IP address
[ "${SSH_SUBNET}" != "" ] && \
  ipaddr=$(ip route|grep '^'"${SSH_SUBNET}"|sed 's/[[:space:]]/\n/g;'|sed '/^[[:space:]]\{0,\}$/d'|tail -n 1)

# Export hostkey and IP address to /root/.ssh/known_hosts
mkdir -p /root/.ssh && chmod 700 /root/.ssh
hostkey="$(cat $(cat /etc/ssh/sshd_config|awk '$1~/^HostKey$/{print($2)}').pub)"
echo "$(hostname) ${hostkey}">/root/.ssh/known_hosts
[ "${ipaddr}" != "" ] && \
  echo "${ipaddr} ${hostkey}">>/root/.ssh/known_hosts

# Make /root/.ssh/known_hosts public if directory /webconsole is
# writeable and create an appropriate .sh file for the ssh command
[ -w /webconsole ] && \
  cp /root/.ssh/known_hosts /webconsole/$(hostname).hostkey && \
  echo "${ipaddr} $(hostname)" > /webconsole/$(hostname).hosts && \
  echo -e "#!/bin/sh\nssh -p ${SSHD_PORT} ${SSH_USER}@$(hostname)">/webconsole/$(hostname).sh && \
  chmod 755 /webconsole/$(hostname).sh


unset SSH_USER
unset SSH_HASH
unset SSH_PASSPHRASE_BASE64

exec "$@"