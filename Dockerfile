FROM container-registry.oracle.com/database/free:23.7.0.0-amd64

USER root

RUN usermod -u 1001 oracle && \
    groupmod -g 1001 oinstall && \
    chown -R oracle:oinstall /opt/oracle /etc/oratab /home/oracle
# RUN chmod -R g+w /opt/oracle/admin/FREE/

# RUN chgrp -R 0 /opt/oracle /etc/oratab
# RUN chmod -R u=g /opt/oracle /etc/oratab /home/oracle
# RUN chmod -R g+w /opt/oracle /etc/oratab /home/oracle
# RUN chmod -R g+w /opt/oracle/admin/FREE/

# RUN chgrp -R 0 /opt/oracle /etc/oratab /home/oracle
# RUN chmod -R u=g /opt/oracle /etc/oratab /home/oracle
# RUN chmod -R g+w /opt/oracle /etc/oratab /home/oracle
# RUN chmod -R o-rwx /opt/oracle /etc/oratab /home/oracle
# echo 'oracle:x:0' >> /etc/group

USER oracle
