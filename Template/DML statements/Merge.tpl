[$query tables =
        select lower(object_name) from user_objects
        where object_type = 'TABLE'
        order by object_name]
merge into 
    [dest=$tables,...] d
using 
(select 
    * 
from 
    [source=$tables,...] ) s
on
    ( <join_condition> )
when matched 
    then update set 
        <update_condition> 
when not_matched 
    then insert
        <source_columns>
values ( <dest_columns>     )
where  ( <filter_condition> )
