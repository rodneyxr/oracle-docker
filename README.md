# Quickstart

## Download APEX

[Download APEX](https://www.oracle.com/tools/downloads/apex-downloads/) zip and extract it to the `./volumes/apex` directory or run the following commands.

```bash
curl https://download.oracle.com/otn_software/apex/apex-latest.zip -o apex-latest.zip
unzip apex-latest.zip "apex/*" -d ./volumes
```
*After, you should have `./volumes/apex/{builder,core,images,*.sql}`*

# Start the services

```bash
docker-compose up -d
```

## Install APEX

Install APEX on the DB.

```bash
docker-compose exec -it db bash
cd /opt/oracle/apex
sqlplus sys/password@XEPDB1 as sysdba
@apexins.sql SYSAUX SYSAUX TEMP /i/
@apxchpwd.sql
ALTER USER APEX_PUBLIC_USER ACCOUNT UNLOCK;
exit
exit
```

## Install ORDS

```bash
docker-compose exec -it ords ords --config /etc/ords/config install --admin-user SYS --proxy-user --feature-sdw true --gateway-user APEX_PUBLIC_USER --gateway-mode proxied --db-hostname db --db-port 1521 --db-servicename XEPDB1
```

Restart ORDS.

```bash
docker-compose restart ords
```

## Access ORDS/APEX

ORDS: [http://localhost:8080/ords](http://localhost:8080/ords).

APEX: [http://localhost:8080/ords/apex](http://localhost:8080/ords/apex)

- Workspace: `INTERNAL`
- Username: `ADMIN`
- Password: `<YOUR_PASSWORD>`

# Other Notes

Access DB in one shot.

```bash
docker-compose exec -it db sqlplus sys/password@XEPDB1 as sysdba
```

Allowing a user to connect through the ORDS_PUBLIC_USER gateway user

```sql
alter user MYUSER grant connect through ORDS_PUBLIC_USER;
```

If user is locked when logging into APEX.

```sql
ALTER USER APEX_PUBLIC_USER ACCOUNT UNLOCK;
```

Show APEX users.

```sql
select username from all_users where username like 'APEX%';
select user_name from APEX_240200.wwv_flow_fnd_user;
```