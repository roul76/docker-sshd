#!/bin/sh
set -o pipefail

# Create login user
[ "${SSH_USER}" != "" ] && [ "${SSH_HASH}" != "" ] && \
  adduser -S -h /home/"${SSH_USER}" -s "/bin/zsh" "${SSH_USER}" && \
  echo "${SSH_USER}:${SSH_HASH}"|chpasswd -e

# Retrieve own IP address
[ "${SSH_SUBNET}" != "" ] && \
  ipaddr=$(ip route|grep '^'"${SSHD_SUBNET}"|sed 's/[[:space:]]/\n/g;'|sed '/^[[:space:]]\{0,\}$/d'|tail -n 1)

# Restrict connections only from SSHD_SUBNET
iptables -A INPUT -p tcp --dport "${SSHD_PORT}" --source "${SSHD_SUBNET}" -j ACCEPT
iptables -A INPUT -j DROP

# Allow access to certain networks
if [ "${SSH_ACCESSIBLE_NETWORKS}" != "" ]; then
  echo "${SSH_ACCESSIBLE_NETWORKS}"|sed 's/|/\n/g'|while read n; do
    iptables -A OUTPUT -d "${n}" -j ACCEPT
  done
fi

# Deny access to any other network
iptables -A OUTPUT -j DROP

# Export hostkey and IP address to /root/.ssh/known_hosts
mkdir -p /root/.ssh && chmod 700 /root/.ssh
hostkey="$(cat $(cat /etc/ssh/sshd_config|awk '$1~/^HostKey$/{print($2)}').pub)"
echo "$(hostname) ${hostkey}">/root/.ssh/known_hosts
[ "${ipaddr}" != "" ] && \
  echo "${ipaddr} ${hostkey}">>/root/.ssh/known_hosts

# Make it public if directory /webconsole is writeable
# and create an appropriate .sh file for the ssh command
[ -w /webconsole ] && \
  cp /root/.ssh/known_hosts /webconsole/$(hostname).hostkey && \
  echo "${ipaddr} $(hostname)" > /webconsole/$(hostname).hosts && \
  echo -e "#!/bin/sh\nssh -p ${SSHD_PORT} ${SSH_USER}@$(hostname)">/webconsole/$(hostname).sh && \
  chmod 755 /webconsole/$(hostname).sh

unset SSH_USER
unset SSH_HASH

exec "$@"