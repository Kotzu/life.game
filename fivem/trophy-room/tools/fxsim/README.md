# fxsim — headless FXServer-environment simulator

Runs the **real** `kotzu_trophy_room` server scripts (unmodified) against a
**real** MariaDB, with the FXServer server-side natives and oxmysql shimmed.
Used because the official FXServer artifacts are unreachable from the cloud dev
environment; on a workstation, prefer a real FXServer.

```
# requirements: lua5.4, mariadb client+server running on a socket
FXSIM_MYSQL_SOCKET=/run/mysqld/mysqld.sock FXSIM_MYSQL_DB=ktr_sim lua5.4 run.lua
```

The target database is DROPPED and recreated each run. Exit code 0 = all
scenarios pass. See `docs/headless-verification-report.md` for the scenario
list and the latest results (`last_run.txt`).

Files: `shim.lua` (natives/events/scheduler/players), `mysql_shim.lua`
(oxmysql surface over the mariadb CLI), `json.lua` (minimal JSON), `run.lua`
(scenarios S1–S11).
