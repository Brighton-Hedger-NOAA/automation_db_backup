SET VERIFY OFF
SET FEEDBACK OFF
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LONG 2000000
SET PAGESIZE 0
SET HEADING OFF
SET TRIMSPOOL ON
SET LINESIZE 32767

-- This script uses a PL/SQL block to handle different export types.
-- &1 = The export mode (e.g., 'TABLE', 'DATA')
-- &2 = The object name
DECLARE
    -- Variables for data export
    l_sql       CLOB;
    l_col_list  CLOB;
    l_val_list  CLOB;
    l_val       VARCHAR2(32767);
    l_date_val  DATE;
    l_num_val   NUMBER;
    -- Variable for DDL output
    v_ddl       CLOB;
BEGIN
    -- Use a CASE statement to determine which action to perform based on the mode (&1)
    CASE UPPER('&1')
        WHEN 'SEQUENCE' THEN
            SELECT DBMS_METADATA.GET_DDL('SEQUENCE', '&2') INTO v_ddl FROM DUAL;
            DBMS_OUTPUT.PUT_LINE(v_ddl);

        WHEN 'TABLE' THEN
            EXECUTE IMMEDIATE 'BEGIN DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, ''CONSTRAINTS'', false); END;';
            EXECUTE IMMEDIATE 'BEGIN DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, ''REF_CONSTRAINTS'', false); END;';
            SELECT DBMS_METADATA.GET_DDL('TABLE', '&2') INTO v_ddl FROM DUAL;
            DBMS_OUTPUT.PUT_LINE(v_ddl);

        WHEN 'VIEW' THEN
            SELECT DBMS_METADATA.GET_DDL('VIEW', '&2') INTO v_ddl FROM DUAL;
            DBMS_OUTPUT.PUT_LINE(v_ddl);

        WHEN 'TRIGGER' THEN
            SELECT DBMS_METADATA.GET_DDL('TRIGGER', '&2') INTO v_ddl FROM DUAL;
            DBMS_OUTPUT.PUT_LINE(v_ddl);

        WHEN 'TABLE_CONSTRAINTS' THEN
            EXECUTE IMMEDIATE 'BEGIN DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM, ''CONSTRAINTS_AS_ALTER'', true); END;';
            SELECT DBMS_METADATA.GET_DEPENDENT_DDL('CONSTRAINT', '&2') INTO v_ddl FROM DUAL;
            DBMS_OUTPUT.PUT_LINE(v_ddl);
            
        WHEN 'DATA' THEN
            -- Build the column list for the INSERT statement
            FOR c IN (SELECT column_name, ROWNUM AS rn, COUNT(*) OVER () AS total_cols FROM user_tab_columns WHERE table_name = UPPER('&2') ORDER BY column_id) LOOP
                l_col_list := l_col_list || '"' || c.column_name || '"';
                IF c.rn < c.total_cols THEN
                    l_col_list := l_col_list || ', ';
                END IF;
            END LOOP;
            -- Loop through each row of the target table
            FOR r IN (SELECT rowid AS rid FROM "&&2") LOOP
                l_val_list := '';
                FOR c IN (SELECT column_name, data_type, ROWNUM AS rn, COUNT(*) OVER () AS total_cols FROM user_tab_columns WHERE table_name = UPPER('&2') ORDER BY column_id) LOOP
                    IF c.data_type LIKE '%CHAR%' OR c.data_type LIKE '%CLOB%' THEN
                        EXECUTE IMMEDIATE 'SELECT "' || c.column_name || '" FROM "' || UPPER('&2') || '" WHERE rowid = :rid' INTO l_val USING r.rid;
                        IF l_val IS NULL THEN l_val_list := l_val_list || 'NULL'; ELSE l_val_list := l_val_list || '''' || REPLACE(l_val, '''', '''''') || ''''; END IF;
                    ELSIF c.data_type = 'DATE' THEN
                        EXECUTE IMMEDIATE 'SELECT "' || c.column_name || '" FROM "' || UPPER('&2') || '" WHERE rowid = :rid' INTO l_date_val USING r.rid;
                        IF l_date_val IS NULL THEN l_val_list := l_val_list || 'NULL'; ELSE l_val_list := l_val_list || 'TO_DATE(''' || TO_CHAR(l_date_val, 'YYYY-MM-DD') || ''', ''YYYY-MM-DD'')'; END IF;
                    ELSE -- Handles NUMBER, etc.
                        EXECUTE IMMEDIATE 'SELECT "' || c.column_name || '" FROM "' || UPPER('&2') || '" WHERE rowid = :rid' INTO l_num_val USING r.rid;
                        IF l_num_val IS NULL THEN l_val_list := l_val_list || 'NULL'; ELSE l_val_list := l_val_list || l_num_val; END IF;
                    END IF;
                    IF c.rn < c.total_cols THEN l_val_list := l_val_list || ', '; END IF;
                END LOOP;
                l_sql := 'INSERT INTO "' || UPPER('&2') || '" (' || l_col_list || ') VALUES (' || l_val_list || ');';
                DBMS_OUTPUT.PUT_LINE(l_sql);
            END LOOP;
            
        WHEN 'GENERIC' THEN
             -- &2 is object type, &3 is object name
            SELECT DBMS_METADATA.GET_DDL('&2', '&3') INTO v_ddl FROM DUAL;
            DBMS_OUTPUT.PUT_LINE(v_ddl);

    END CASE;
END;
/