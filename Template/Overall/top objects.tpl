select *
  from (SELECT to_char(min(begin_interval_time), 'DD-Mon-YY HH24:MI') ||
               ' - ' ||
               to_char(max(begin_interval_time), 'DD-Mon-YY HH24:MI') as WHEN,
               dhso.object_name,
               sum(db_block_changes_delta) as db_block_changes,
               to_char(round((RATIO_TO_REPORT(sum(db_block_changes_delta)) OVER()) * 100, 2), '99.00') as REDO_PERCENT
          FROM dba_hist_seg_stat     dhss,
               dba_hist_seg_stat_obj dhso,
               dba_hist_snapshot     dhs
         WHERE dhs.snap_id = dhss.snap_id
           AND dhs.instance_number = dhss.instance_number
           AND dhss.obj# = dhso.obj#(+)
           AND dhss.dataobj# = dhso.dataobj#(+)
           AND begin_interval_time BETWEEN
               to_date('&1', 'DD-Mon-YY HH24:MI') AND
               to_date('&2', 'DD-Mon-YY HH24:MI')
         GROUP BY dhso.object_name
         ORDER BY db_block_changes desc)
 where rownum <= &3 ;
 
 
