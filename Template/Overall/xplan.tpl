select * from table ( dbms_xplan.display_cursor(sql_id => '[sql_id]', cursor_child_no => [cursor_child = 0], format => 'ALLSTATS ADAPTIVE -OUTLINE -PREDICATE -PROJECTION'));
