with
 ash0 as (select * from Gv$active_session_history),
 sid_time as -- List of sessions and their start/stop times
 (select nvl(qc_session_id, session_id) as qc_session_id,
         session_id,
         session_serial#,
         sql_id,
         min(sample_time) as MIN_SQL_EXEC_TIME,
         max(sample_time) as MAX_SQL_EXEC_TIME
    from ash0
   where sql_id = [sqlid]
     and NVL(sql_plan_hash_value, 0) = nvl([sqlplan], NVL(sql_plan_hash_value, 0))
     and NVL(sql_exec_id, 0) = nvl([sqlexec], NVL(sql_exec_id, 0))
   group by nvl(qc_session_id, session_id), session_id, session_serial#, sql_id, sql_plan_hash_value, sql_exec_id)
, ash as (                               -- ASH part, consisting of direct SQL exec ONLy
  select count(distinct sh.session_id||sh.session_serial#) as SID_COUNT,
         0 as plsql_entry_object_id,     -- important for recrsv queries only
         0 as plsql_entry_subprogram_id, -- --//--
         sh.sql_id,
         NVL2(sql_exec_id,1,null) as SQL_EXEC_ID,
         nvl(sql_plan_hash_value, 0)                         as SQL_PLAN_HASH_VALUE,
         nvl(sql_plan_line_id, 0)                            as SQL_PLAN_LINE_ID,
         decode(session_state,'WAITING',event,session_state) as EVENT,
         count(*)                                            as WAIT_COUNT,
         min(sample_time)                                    as MIN_SAMPLE_TIME,
         max(sample_time)                                    as MAX_SAMPLE_TIME
    from ash0 sh
   where (sh.sql_id              = [sqlid] and                                -- direct SQL exec ONLY
          sh.sql_plan_hash_value = nvl([sqlplan], sh.sql_plan_hash_value) and
          NVL(sh.sql_exec_id, 0) = nvl([sqlexec], NVL(sh.sql_exec_id, 0)))
   group by sh.sql_id, NVL2(sql_exec_id,1,null), nvl(sql_plan_hash_value, 0), nvl(sql_plan_line_id, 0), decode(session_state,'WAITING',event,session_state))
, ash_stat as ( -- direct SQL exec stats
select  sql_id,
        SQL_EXEC_ID,
        sql_plan_hash_value,
        sql_plan_line_id,
        sum(WAIT_COUNT) as ASH_ROWS,
        rtrim(xmlagg(xmlelement(s, EVENT || '(' || WAIT_COUNT, '); ').extract('//text()') order by WAIT_COUNT desc)--.getclobval ()
                                                                                                                   ,'; ') as WAIT_PROFILE,
        max(SID_COUNT)-1 as PX_COUNT,
        max(MAX_SAMPLE_TIME) as MAX_SAMPLE_TIME
from ash
group by sql_id,
         sql_exec_id,
         sql_plan_hash_value,
         sql_plan_line_id)
, ash_recrsv as ( -- ASH part, consisting of indirect / recursive SQLs execs ONLy
  select count(distinct sh.session_id||sh.session_serial#) as SID_COUNT,
         decode(sh.sql_id, sid_time.sql_id, 0, sh.plsql_entry_object_id)     as plsql_entry_object_id,    -- for recrsv queries only
         decode(sh.sql_id, sid_time.sql_id, 0, sh.plsql_entry_subprogram_id) as plsql_entry_subprogram_id,-- --//--
         sh.sql_id,
         nvl(sql_plan_hash_value, 0)                         as SQL_PLAN_HASH_VALUE,
         nvl(sql_plan_line_id, 0)                            as SQL_PLAN_LINE_ID,
         decode(session_state,'WAITING',event,session_state) as EVENT,
         count(*)                                            as WAIT_COUNT,
         min(sample_time)                                    as MIN_SAMPLE_TIME,
         max(sample_time)                                    as MAX_SAMPLE_TIME
    from ash0 sh, sid_time
   where ((sh.top_level_sql_id = sid_time.sql_id and sh.sql_id != sid_time.sql_id or sh.sql_id is null) and-- recursive SQLs
          sh.session_id       = sid_time.session_id and
          sh.session_serial#  = sid_time.session_serial# and
          nvl(sh.qc_session_id, sh.session_id) = sid_time.qc_session_id and
          sh.sample_time between sid_time.MIN_SQL_EXEC_TIME and sid_time.MAX_SQL_EXEC_TIME)
   group by sh.sql_id, nvl(sql_plan_hash_value, 0), nvl(sql_plan_line_id, 0), decode(session_state,'WAITING',event,session_state),
            decode(sh.sql_id, sid_time.sql_id, 0, sh.plsql_entry_object_id),
            decode(sh.sql_id, sid_time.sql_id, 0, sh.plsql_entry_subprogram_id))
, ash_stat_recrsv as ( -- recursive SQLs stats
select  ash.plsql_entry_object_id,
        ash.plsql_entry_subprogram_id,
        ash.sql_id,
        sql_plan_hash_value,
        sql_plan_line_id,
        sum(WAIT_COUNT) as ASH_ROWS,
        rtrim(xmlagg(xmlelement(s, EVENT || '(' ||WAIT_COUNT, '); ').extract('//text()') order by WAIT_COUNT desc)--.getclobval ()
                                                                                                                  ,'; ') as WAIT_PROFILE,
        max(SID_COUNT)-1 as PX_COUNT,
        max(MAX_SAMPLE_TIME) as MAX_SAMPLE_TIME
from ash_recrsv ash --join sid_time on ash.sql_id <> sid_time.sql_id or ash.sql_id is null
group by ash.plsql_entry_object_id,
         ash.plsql_entry_subprogram_id,
         ash.sql_id,
         sql_plan_hash_value,
         sql_plan_line_id)
, pt as( -- Plan Tables for all excuted SQLs (direct+recursive)
select   sql_id,
         plan_hash_value,
         id,
         operation,
         options,
         object_owner,
         object_name,
         qblock_name,
         nvl(parent_id, -1) as parent_id
    from dba_hist_sql_plan
   where (sql_id, plan_hash_value) in (select sql_id, sql_plan_hash_value from ash union select sql_id, sql_plan_hash_value from ash_recrsv)
  union                                          -- for plans not in dba_hist_sql_plan yet
  select distinct
         sql_id,
         plan_hash_value,
         id,
         operation,
         options,
         object_owner,
         object_name,
         qblock_name,
         nvl(parent_id, -1) as parent_id
    from gv$sql_plan
   where (sql_id, plan_hash_value) in (select sql_id, sql_plan_hash_value from ash union select sql_id, sql_plan_hash_value from ash_recrsv)
  union                                          -- for plans not in dba_hist_sql_plan not v$sql_plan (read-only standby for example)
  select distinct
         sql_id,
         sql_plan_hash_value as plan_hash_value,
         sql_plan_line_id    as id,
         sql_plan_operation  as operation,
         sql_plan_options    as options,
         owner               as object_owner,
         object_name,
         ''                  as qblock_name,
         -2                  as parent_id
    from ash0 left join dba_objects on current_obj# = object_id
   where (sql_id, sql_plan_hash_value) in (select sql_id, sql_plan_hash_value from ash union select sql_id, sql_plan_hash_value from ash_recrsv)
     and (sql_id, sql_plan_hash_value) not in (select sql_id, plan_hash_value from gv$sql_plan union all select sql_id, plan_hash_value from dba_hist_sql_plan))
select 'Hard Parse' as LAST_PLSQL, -- the hard parse phase, sql plan does not exists yet, sql_plan_hash_value = 0
       sql_id,
       sql_plan_hash_value as plan_hash_value,
       ash_stat.sql_plan_line_id as ID,
       'sql_plan_hash_value = 0' as PLAN_OPERATION,
       null as object_owner,
       null as object_name,
       null as QBLOCK_NAME,
       ash_stat.PX_COUNT as PX,
       ash_stat.ASH_ROWS,
       ash_stat.WAIT_PROFILE
  from ash_stat
 where sql_plan_hash_value = 0
UNION ALL
select 'Soft Parse' as LAST_PLSQL, -- the soft parse phase, sql plan exists but execution didn't start yet, sql_exec_id is null
       sql_id,              
       sql_plan_hash_value as plan_hash_value,
       ash_stat.sql_plan_line_id as ID,
       'sql_plan_hash_value > 0; sql_exec_id is null' as PLAN_OPERATION,
       null as object_owner,
       null as object_name,
       null as QBLOCK_NAME,
       ash_stat.PX_COUNT as PX,
       ash_stat.ASH_ROWS,
       ash_stat.WAIT_PROFILE
  from ash_stat
 where sql_plan_hash_value > 0
   and sql_exec_id is null
UNION ALL
SELECT 'Main Query w/o saved plan'       -- direct SQL which plan not in gv$sql_plan, dba_hist_sql_plan (ro-standby)
                                                                 as LAST_PLSQL,
       pt.sql_id                                                 as SQL_ID,
       pt.plan_hash_value                                        as plan_hash_value,
       pt.id,
       lpad(' ', id) || pt.operation || ' ' || pt.options        as PLAN_OPERATION,
       pt.object_owner,
       pt.object_name,
       pt.qblock_name,
       ash_stat.PX_COUNT                                         as PX,
       ash_stat.ASH_ROWS,
       ash_stat.WAIT_PROFILE
  FROM pt
  left join ash_stat
  on --pt.parent_id       = -2 and
     pt.id              = NVL(ash_stat.sql_plan_line_id,0) and
     pt.sql_id          = ash_stat.sql_id and
     pt.plan_hash_value = ash_stat.sql_plan_hash_value         -- sql_plan_hash_value > 0
                      and ash_stat.sql_exec_id is not null
  where pt.parent_id       = -2
UNION ALL
SELECT case when pt.id =0 then 'Main Query' -- direct SQL plan+stats
            when ash_stat.MAX_SAMPLE_TIME > sysdate - 10/86400 then '>>>'
            when ash_stat.MAX_SAMPLE_TIME > sysdate - 30/86400 then '>> '
            when ash_stat.MAX_SAMPLE_TIME > sysdate - 60/86400 then '>  '
            else '   ' end as LAST_PLSQL,
       decode(pt.id, 0, pt.sql_id, null) as SQL_ID,
       decode(pt.id, 0, pt.plan_hash_value, null) as plan_hash_value,
       pt.id,
       lpad(' ', 2 * level) || pt.operation || ' ' || pt.options as PLAN_OPERATION,
       pt.object_owner,
       pt.object_name,
       pt.qblock_name,
       ash_stat.PX_COUNT as PX,
       ash_stat.ASH_ROWS,
       ash_stat.WAIT_PROFILE
  FROM pt
  left join ash_stat
  on pt.id              = NVL(ash_stat.sql_plan_line_id,0) and
     pt.sql_id          = ash_stat.sql_id and
     pt.plan_hash_value = ash_stat.sql_plan_hash_value         -- sql_plan_hash_value > 0
                      and ash_stat.sql_exec_id is not null
  where pt.sql_id in (select sql_id from ash_stat)
CONNECT BY PRIOR pt.id = pt.parent_id
       and PRIOR pt.sql_id = pt.sql_id
       and PRIOR pt.plan_hash_value = pt.plan_hash_value
 START WITH pt.id = 0
UNION ALL
SELECT decode(pt.id, 0, p.object_name||'.'||p.procedure_name, null) as LAST_PLSQL, -- recursive SQLs plan+stats
       decode(pt.id, 0, pt.sql_id, null) as SQL_ID,
       decode(pt.id, 0, pt.plan_hash_value, null) as plan_hash_value,
       pt.id,
       lpad(' ', 2 * level) || pt.operation || ' ' || pt.options as PLAN_OPERATION,
       pt.object_owner,
       pt.object_name,
       pt.qblock_name,
       ash_stat.PX_COUNT as PX,
       ash_stat.ASH_ROWS,
       ash_stat.WAIT_PROFILE
  FROM pt
  left join ash_stat_recrsv ash_stat
  on pt.id              = NVL(ash_stat.sql_plan_line_id,0) and
     pt.sql_id          = ash_stat.sql_id and
    (pt.plan_hash_value = ash_stat.sql_plan_hash_value or ash_stat.sql_plan_hash_value = 0)
  left join dba_procedures p on ash_stat.plsql_entry_object_id     = p.object_id and
                                ash_stat.plsql_entry_subprogram_id = p.subprogram_id
  where pt.sql_id in (select sql_id from ash_stat_recrsv)
CONNECT BY PRIOR pt.id = pt.parent_id
       and PRIOR pt.sql_id = pt.sql_id
       and PRIOR pt.plan_hash_value = pt.plan_hash_value
 START WITH pt.id = 0
UNION ALL
select 'Recurs.waits' as LAST_PLSQL, -- non-identified SQL (PL/SQL?) exec stats
       '',
       0 as plan_hash_value,
       ash_stat.sql_plan_line_id,
       'sql_id is null and plsql_entry_object_id is null' as PLAN_OPERATION,
       null,
       null,
       null,
       ash_stat.PX_COUNT as PX,
       ash_stat.ASH_ROWS,
       ash_stat.WAIT_PROFILE
  from ash_stat_recrsv ash_stat
 where sql_id is null
   and ash_stat.plsql_entry_object_id is null
UNION ALL
select 'PL/SQL' as LAST_PLSQL, -- non-identified SQL (PL/SQL?) exec stats
       '',
       0 as plan_hash_value,
       ash_stat.sql_plan_line_id,
       p.owner ||' '|| p.object_name||'.'||p.procedure_name as PLAN_OPERATION,
       null,
       null,
       null,
       ash_stat.PX_COUNT as PX,
       ash_stat.ASH_ROWS,
       ash_stat.WAIT_PROFILE
  from ash_stat_recrsv ash_stat
  join dba_procedures p on ash_stat.plsql_entry_object_id     = p.object_id and
                                ash_stat.plsql_entry_subprogram_id = p.subprogram_id
 where sql_id is null;

