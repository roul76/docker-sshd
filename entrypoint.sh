#!/bin/ash
set -eo pipefail

echo "*** Start initalization ***"

# Limit incoming traffic to SSH_SUBNET on port SSHD_PORT
if [ "${SSH_SUBNET}" != "" -a "${SSHD_PORT}" != "" ]; then
  echo "Limit incoming traffic to ${SSH_SUBNET} on port ${SSHD_PORT}"

  iptables -A INPUT -s "${SSH_SUBNET}" -p tcp --dport "${SSHD_PORT}" -j ACCEPT
  iptables -A OUTPUT -d "${SSH_SUBNET}" -p tcp --sport "${SSHD_PORT}" -m state --state ESTABLISHED -j ACCEPT
fi

# Set IPv4 nameservers if provided
if [ "${SSH_NAMESERVERS}" != "" ]; then
  echo "Set IPv4 nameservers:"

  echo "${SSH_NAMESERVERS}"|sed 's/|/\n/g'|while read n; do
    echo "- ${n}"

    echo "nameserver ${n}" >> /etc/resolv.conf
    iptables -A OUTPUT -p udp -d "${n}/32" --dport 53 -m state --state NEW,ESTABLISHED -j ACCEPT
    iptables -A INPUT  -p udp -s "${n}/32" --sport 53 -m state --state ESTABLISHED -j ACCEPT
    iptables -A OUTPUT -p tcp -d "${n}/32" --dport 53 -m state --state NEW,ESTABLISHED -j ACCEPT
    iptables -A INPUT  -p tcp -s "${n}/32" --sport 53 -m state --state ESTABLISHED -j ACCEPT
  done
fi

# Allow access to certain networks listed in SSH_ACCESSIBLE_NETWORKS
if [ "${SSH_ACCESSIBLE_NETWORKS}" != "" ]; then
  echo "Allow access to certain networks:"

  echo "${SSH_ACCESSIBLE_NETWORKS}"|sed 's/|/\n/g'|while read n; do
    echo "- ${n}"

    iptables -A OUTPUT -d "${n}" -j ACCEPT
    iptables -A INPUT -s "${n}" -m state --state ESTABLISHED -j ACCEPT
  done
fi

# Apply DROP policies to any other network traffic
echo "Apply DROP policies to any other network traffic"
iptables -P OUTPUT DROP
iptables -P INPUT DROP
iptables -P FORWARD DROP

# Create login user
if [ "${SSH_USER}" != "" -a "${SSH_HASH}" != "" ]; then
  [ "${SSH_USER_ID}" = "" ] && SSH_USER_ID=1001
  echo "Adding group 'webconsole' with GID ${SSH_USER_ID}"
  addgroup -g "${SSH_USER_ID}" webconsole

  echo "Adding user '${SSH_USER}' with UID ${SSH_USER_ID}"
  adduser -u "${SSH_USER_ID}" -G webconsole -D -h /home/"${SSH_USER}" -s "/bin/zsh" "${SSH_USER}"

  echo "Changing password for user '${SSH_USER}'"
  echo "${SSH_USER}:${SSH_HASH}"|chpasswd -e

  echo "Creating ~/.zshrc"
  touch "/home/${SSH_USER}/.zshrc"
  chown "${SSH_USER}" "/home/${SSH_USER}/.zshrc"
  chmod 640 "/home/${SSH_USER}/.zshrc"
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

  if [ "$(find "${SSH_KEY_DIRECTORY}/" -name "*.key*" -type f 2>/dev/null)" != "" ]; then
    echo "echo "'"'"
*** SSH key files stored in ${SSH_KEY_DIRECTORY} ***
"'"'>>"/home/${SSH_USER}/.zshrc"
  fi
fi

# Export hostkey and IP address to /root/.ssh/known_hosts
echo "Exporting hostname and hostkey to /root/.ssh/known_hosts"
mkdir -p /root/.ssh
chmod 700 /root/.ssh
hostkey="$(cat "$(awk '$1~/^HostKey$/{print($2)}'</etc/ssh/sshd_config)".pub)"
echo "$(hostname) ${hostkey}">/root/.ssh/known_hosts

if [ "${SSH_SUBNET}" != "" ]; then
  # Retrieve own IP address
  ipaddr=$(ip route|grep '^'"${SSH_SUBNET}"|sed 's/[[:space:]]/\n/g;'|sed '/^[[:space:]]\{0,\}$/d'|tail -n 1)
  if [ "${ipaddr}" != "" ]; then
    echo "Exporting IP address and hostkey to /root/.ssh/known_hosts"
    echo "${ipaddr} ${hostkey}">>/root/.ssh/known_hosts
  fi
fi

# Make /root/.ssh/known_hosts public if directory /webconsole is
# writeable and create an appropriate .sh file for the ssh command
if [ -w /webconsole ]; then
  fileprefix="/webconsole/$(hostname)"

  echo "Exporting /root/.ssh/known_hosts to ${fileprefix}.hostkey"
  cp /root/.ssh/known_hosts "${fileprefix}.hostkey"

  echo "Exporting IP address and hostname to ${fileprefix}.hosts"
  echo "${ipaddr} $(hostname)" > "${fileprefix}.hosts"

  echo "Creating login script ${fileprefix}.sh"
  echo -e "#!/bin/sh\nssh -p ${SSHD_PORT} ${SSH_USER}@$(hostname)">"${fileprefix}.sh"
  chmod 755 "${fileprefix}.sh"
fi

unset SSH_USER
unset SSH_HASH
unset SSH_PASSPHRASE_BASE64

echo "*** Finished initialization ***"
exec "$@"