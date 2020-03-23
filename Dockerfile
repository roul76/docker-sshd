FROM alpine:3.10
LABEL maintainer="https://github.com/roul76"

ENV SSHD_PORT=7576 \
    NOTVISIBLE="in users profile"

RUN apk add --no-cache openssh-client openssh-server linux-pam zsh screen iptables && \
    mkdir /var/run/sshd && \
    sed ' \
      s/^[#]*\(Port\).*$/\1 '${SSHD_PORT}'/; \
      s/^[#]*\(PermitRootLogin\).*$/\1 no/; \
      s/^[#]*\(PasswordAuthentication\).*$/\1 yes/ ; \
      s/^[#]*\(LoginGraceTime\).*/\1 120/ ; \
      s/^[#]*\(StrictModes\).*/\1 yes/ ; \
      s/^[#]*\(PubkeyAuthentication\).*/\1 no/ ; \
      s/^[#]*\(UsePAM\).*/\1 yes/ ; \
      s/^[#]*\(HostKey.*rsa.*\)/\1/ \
    ' -i /etc/ssh/sshd_config && \
    ssh-keygen -f "$(cat /etc/ssh/sshd_config | awk '$1~/^HostKey$/{print($2)}')" -N '' -t rsa >/dev/null && \
    echo -e "account		include				base-account\nauth		required			pam_env.so\nauth		required			pam_nologin.so	successok">/etc/pam.d/sshd && \
    echo "" > /etc/motd && \
    echo -e "export VISIBLE=now\nexport PS1='$ '" >> /etc/profile

COPY ./entrypoint.sh /bin/entrypoint.sh
RUN chmod 555 /bin/entrypoint.sh

EXPOSE ${SSHD_PORT}
ENTRYPOINT [ "/bin/entrypoint.sh" ]
CMD ["/usr/sbin/sshd", "-D"]