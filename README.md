# Quickstart

## Download APEX

[Download APEX](https://www.oracle.com/tools/downloads/apex-downloads/) zip and extract it to the `./volumes/apex` directory.

```bash
unzip apex-latest.zip -d ./volumes
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
exit
```

## Install ORDS

```bash
docker-compose exec -it ords bash
ords --config /etc/ords/config install --admin-user SYS --proxy-user --feature-sdw true --gateway-user APEX_PUBLIC_USER --gateway-mode proxied
exit
```

Restart ORDS.

```bash
docker-compose restart ords
```

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