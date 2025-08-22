SET VERIFY OFF
SET FEEDBACK OFF
SET SERVEROUTPUT ON SIZE UNLIMITED

DECLARE
    l_sql       CLOB;
    l_col_list  CLOB;
    l_val_list  CLOB;
    l_val       VARCHAR2(32767);
    l_date_val  DATE;
    l_num_val   NUMBER;
BEGIN
    -- Build the column list for the INSERT statement
    FOR c IN (SELECT column_name, ROWNUM AS rn, COUNT(*) OVER () AS total_cols FROM user_tab_columns WHERE table_name = UPPER('&1') ORDER BY column_id) LOOP
        l_col_list := l_col_list || '"' || c.column_name || '"';
        IF c.rn < c.total_cols THEN
            l_col_list := l_col_list || ', ';
        END IF;
    END LOOP;

    -- Loop through each row of the target table using its rowid
    FOR r IN (SELECT rowid AS rid FROM "&&1") LOOP
        l_val_list := '';
        -- Loop through each column for the current row
        FOR c IN (SELECT column_name, data_type, ROWNUM AS rn, COUNT(*) OVER () AS total_cols FROM user_tab_columns WHERE table_name = UPPER('&1') ORDER BY column_id) LOOP
            
            -- Correctly handle different data types
            IF c.data_type LIKE '%CHAR%' OR c.data_type LIKE '%CLOB%' THEN
                EXECUTE IMMEDIATE 'SELECT "' || c.column_name || '" FROM "' || UPPER('&1') || '" WHERE rowid = :rid' INTO l_val USING r.rid;
                IF l_val IS NULL THEN
                    l_val_list := l_val_list || 'NULL';
                ELSE
                    l_val_list := l_val_list || '''' || REPLACE(l_val, '''', '''''') || '''';
                END IF;
            ELSIF c.data_type = 'DATE' THEN
                EXECUTE IMMEDIATE 'SELECT "' || c.column_name || '" FROM "' || UPPER('&1') || '" WHERE rowid = :rid' INTO l_date_val USING r.rid;
                IF l_date_val IS NULL THEN
                    l_val_list := l_val_list || 'NULL';
                ELSE
                    l_val_list := l_val_list || 'TO_DATE(''' || TO_CHAR(l_date_val, 'YYYY-MM-DD HH24:MI:SS') || ''', ''YYYY-MM-DD HH24:MI:SS'')';
                END IF;
            ELSE -- Handles NUMBER, etc.
                EXECUTE IMMEDIATE 'SELECT "' || c.column_name || '" FROM "' || UPPER('&1') || '" WHERE rowid = :rid' INTO l_num_val USING r.rid;
                IF l_num_val IS NULL THEN
                    l_val_list := l_val_list || 'NULL';
                ELSE
                    l_val_list := l_val_list || l_num_val;
                END IF;
            END IF;

            IF c.rn < c.total_cols THEN
                l_val_list := l_val_list || ', ';
            END IF;
        END LOOP;
        
        -- Assemble and print the final INSERT statement
        l_sql := 'INSERT INTO "' || UPPER('&1') || '" (' || l_col_list || ') VALUES (' || l_val_list || ');';
        DBMS_OUTPUT.PUT_LINE(l_sql);
    END LOOP;
END;
/