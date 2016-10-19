declare
    v_clob  clob;
    v_ident varchar2(100 char);
    v_sql := '[#]'
begin
    -- включили 
    v_ident := ut.ut_trace.enable_trace;  
    execute immediate v_sql;
    dbms_output.put_line(v_ident); 
     -- выключили 
     ut.ut_trace.disable_trace;  
end;
/     
     
select * from ut.ut_udump_data;
