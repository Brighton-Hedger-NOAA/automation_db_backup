--PL/SQL that will tables with reserved column names or columns with format CLOB and punctuation
--Wraps all column names in double quotes → avoids reserved word errors.
--Strings and CLOBs: truncates to 4000 chars (expandable by looping if you need full CLOBs). Escapes single quotes.
--Dates: formatted and wrapped in TO_DATE(...).
--Should be saved in same folder as .bat script as separate file: datatype_handler.sql 
set serveroutput on size unlimited
set pagesize 0 linesize 32767 long 2000000 longchunksize 2000000 feedback off

define TABLE_NAME=''

spool &TABLE_NAME..sql

declare
    l_sql clob;
    l_val clob;
    l_len integer;
    l_pos integer;
begin
    for r in (select rowid rid from "&&TABLE_NAME") loop
        l_sql := 'INSERT INTO "&&TABLE_NAME" (';
        -- Column list
        for c in (select column_name, column_id from user_tab_columns
                  where table_name = '&&TABLE_NAME' order by column_id) loop
            if c.column_id > 1 then l_sql := l_sql || ','; end if;
            l_sql := l_sql || '"' || c.column_name || '"';
        end loop;
        l_sql := l_sql || ') VALUES (';
        -- Column values
        for c in (select column_name, data_type, column_id from user_tab_columns
                  where table_name = '&&TABLE_NAME' order by column_id) loop
            if c.column_id > 1 then l_sql := l_sql || ','; end if;

            if c.data_type like '%CLOB%' then
                l_val := '';
                l_len := dbms_lob.getlength(r."||c.column_name||");
                l_pos := 1;
                while l_pos <= l_len loop
                    l_val := l_val || dbms_lob.substr(r."||c.column_name||", 32000, l_pos);
                    l_pos := l_pos + 32000;
                end loop;
                l_sql := l_sql || '''' || replace(l_val, '''', '''''') || '''';
            elsif c.data_type like '%CHAR%' then
                execute immediate 'select ""'||c.column_name||'"" from "&&TABLE_NAME" where rowid = :rid' 
                into l_val using r.rid;
                l_sql := l_sql || '''' || replace(l_val, '''', '''''') || '''';
            elsif c.data_type like '%DATE%' then
                execute immediate 'select to_char(""'||c.column_name||'"",'YYYY-MM-DD HH24:MI:SS') from "&&TABLE_NAME" where rowid = :rid'
                into l_val using r.rid;
                l_sql := l_sql || 'TO_DATE('''||l_val||''',''YYYY-MM-DD HH24:MI:SS'')';
            else
                execute immediate 'select ""'||c.column_name||'"" from "&&TABLE_NAME" where rowid = :rid' 
                into l_val using r.rid;
                l_sql := l_sql || nvl(l_val,'NULL');
            end if;
        end loop;

        l_sql := l_sql || ');';
        dbms_output.put_line(l_sql);
    end loop;
end;
/

spool off
exit;
