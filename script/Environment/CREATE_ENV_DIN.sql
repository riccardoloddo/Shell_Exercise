-------------------------------------------------------------- 
----------------CREAZIONE NUOVO UTENTE
--------------------------------------------------------------

BEGIN
   EXECUTE IMMEDIATE 'DROP USER SCPT CASCADE';
EXCEPTION
   WHEN OTHERS THEN
      IF SQLCODE != -1940 THEN -- -1940 = cannot drop a user that is currently connected
         RAISE;
      END IF;
END;
/

BEGIN
   EXECUTE IMMEDIATE 'CREATE USER SCPT IDENTIFIED BY SCPT';
EXCEPTION
   WHEN OTHERS THEN
      IF SQLCODE NOT IN (-955, -1920) THEN 
         RAISE;
      END IF;
END;
/


GRANT CONNECT,RESOURCE,DBA TO SCPT;

--------------------------------------------------------------
---------CREAZIONE DELLE DIRECTORY data bad e log
--------------------------------------------------------------
/*BEGIN
  EXECUTE IMMEDIATE 'CREATE OR REPLACE DIRECTORY SCP_DATA_DIR AS ''' || '&1' || '''';
  EXECUTE IMMEDIATE 'CREATE OR REPLACE DIRECTORY SCP_LOG_DIR AS ''' || '&2' || '''';
END;
/*/

BEGIN
   EXECUTE IMMEDIATE 'CREATE OR REPLACE DIRECTORY SCP_DATA_DIR AS ''&1'' ';
   EXECUTE IMMEDIATE 'CREATE OR REPLACE DIRECTORY SCP_BAD_DIR AS ''c:\scp\bad'' ';
   EXECUTE IMMEDIATE 'CREATE OR REPLACE DIRECTORY SCP_LOG_DIR AS ''&2'' ';
END;
/

GRANT EXECUTE, READ, WRITE ON DIRECTORY SYS.SCP_DATA_DIR TO SCPT WITH GRANT OPTION;  
GRANT EXECUTE, READ, WRITE ON DIRECTORY SYS.SCP_BAD_DIR TO SCPT WITH GRANT OPTION;
GRANT EXECUTE, READ, WRITE ON DIRECTORY SYS.SCP_LOG_DIR TO SCPT WITH GRANT OPTION;


--------------------------------------------------------
--  DDL for Sequence 
--------------------------------------------------------

BEGIN
   EXECUTE IMMEDIATE 'CREATE SEQUENCE SCPT.SEQ_ID_CARICAMENTI';
EXCEPTION
   WHEN OTHERS THEN
      IF SQLCODE != -955 THEN RAISE; END IF;
END;
/

BEGIN
   EXECUTE IMMEDIATE 'CREATE SEQUENCE SCPT.SEQ_ID_RUN';
EXCEPTION
   WHEN OTHERS THEN
      IF SQLCODE != -955 THEN RAISE; END IF;
END;
/

BEGIN
   EXECUTE IMMEDIATE 'CREATE SEQUENCE SCPT.SEQ_ID_MASTER';
EXCEPTION
   WHEN OTHERS THEN
      IF SQLCODE != -955 THEN RAISE; END IF;
END;
/

BEGIN
   EXECUTE IMMEDIATE 'CREATE SEQUENCE SCPT.SEQ_ID_LOG';
EXCEPTION
   WHEN OTHERS THEN
      IF SQLCODE != -955 THEN RAISE; END IF;
END;
/

 
--------------------------------------------------------
--  DDL for Table SCP_TAB01_DATA
--------------------------------------------------------

BEGIN
   EXECUTE IMMEDIATE '
      CREATE TABLE SCPT.SCP_TAB01_DATA (
         CF VARCHAR2(16 BYTE), 
         NOME VARCHAR2(100 BYTE),
         COGNOME VARCHAR2(100 BYTE),
         SALARIO NUMBER
      )';
EXCEPTION
   WHEN OTHERS THEN
      IF SQLCODE != -955 THEN RAISE; END IF;
END;
/

BEGIN
   EXECUTE IMMEDIATE '
      CREATE TABLE SCPT.SCP_TAB01_SCARTI (
         ID_PK NUMBER,
         CF VARCHAR2(100 BYTE), 
         NOME VARCHAR2(100 BYTE),
         COGNOME VARCHAR2(100 BYTE),
         SALARIO VARCHAR2(100 BYTE),
         D_INS DATE DEFAULT SYSDATE
      )';
EXCEPTION
   WHEN OTHERS THEN
      IF SQLCODE != -955 THEN RAISE; END IF;
END;
/

-- SCP_TAB_LOG (solo create, senza drop)
BEGIN
   EXECUTE IMMEDIATE '
      CREATE TABLE SCPT.SCP_TAB_LOG (
         ID_LOG      NUMBER PRIMARY KEY,
         DATA_LOG    DATE DEFAULT SYSDATE,
         STEP        VARCHAR2(100 BYTE),
         LOG_MSG     VARCHAR2(4000 BYTE)
      )';
EXCEPTION
   WHEN OTHERS THEN
      IF SQLCODE != -955 THEN RAISE; END IF;
END;
/

   --------------------------------------------------------
--  Procedura
--------------------------------------------------------
create or replace PROCEDURE      SCPT.LOAD_TO_TAB01 AS

  -- Variabili per log
  v_log_msg       VARCHAR2(4000);
  -- v_name_tab_00   VARCHAR2(30);

  -- Cursore dinamico
  TYPE cur_type IS REF CURSOR;
  cur_ext cur_type;

  -- Record per lettura dalla tabella dinamica
  v_cf      VARCHAR2(100);
  v_nome    VARCHAR2(100);
  v_cognome VARCHAR2(100);
  v_salario VARCHAR2(100);
  v_salario_num NUMBER;

  -- Contatori
  v_count_valid NUMBER := 0;
  v_count_scarti NUMBER := 0;

BEGIN
  ----------------------------------------------------------
  -- Recupero nome tabella 00
  ----------------------------------------------------------
  -- v_name_tab_00 := SCPT.f_get_00_name(p_cod_metodo);

  ----------------------------------------------------------
  -- Step 1: Log estrazione dati
  ----------------------------------------------------------
  v_log_msg := 'Step 1: inizio estrazione dati da SCP_TAB01_DATA';
  INSERT INTO SCPT.SCP_TAB_LOG(ID_LOG, DATA_LOG, STEP, LOG_MSG)
    VALUES (SEQ_ID_LOG.NEXTVAL, SYSDATE, 'Step 1', v_log_msg);
  COMMIT;

  ----------------------------------------------------------
  -- Step 2: Tronco SCP_TAB_LOG e SCP_TAB01_SCARTI
  ----------------------------------------------------------
  EXECUTE IMMEDIATE 'TRUNCATE TABLE SCPT.SCP_TAB_LOG';
  EXECUTE IMMEDIATE 'TRUNCATE TABLE SCPT.SCP_TAB01_SCARTI';
  v_log_msg := 'Step 2: truncata SCP_TAB_LOG ed SCP_TAB01_SCARTI';
  INSERT INTO SCPT.SCP_TAB_LOG(ID_LOG, DATA_LOG, STEP, LOG_MSG)
    VALUES (SEQ_ID_LOG.NEXTVAL, SYSDATE, 'Step 2', v_log_msg);
  COMMIT;

  ----------------------------------------------------------
  -- Step 3: Apro cursore dinamico e ciclo dati
  ----------------------------------------------------------
  OPEN cur_ext FOR 'SELECT * FROM SCP_TAB00_DATA' ;

  LOOP
    FETCH cur_ext INTO v_cf, v_nome, v_cognome, v_salario;
    EXIT WHEN cur_ext%NOTFOUND;

    BEGIN
      -- Provo a convertire il salario
      v_salario_num := TO_NUMBER(REPLACE(v_salario, ',', '.'), '9999999990.99', 'NLS_NUMERIC_CHARACTERS = ''.,''');

      -- Controlli sui dati
      IF LENGTH(v_cf) <= 16
         AND REGEXP_LIKE(v_nome, '^[[:alpha:][:space:]]+$')
         AND REGEXP_LIKE(v_cognome, '^[[:alpha:][:space:]]+$')
         AND v_salario_num > 0
      THEN
         -- Inserisco nella tabella finale
         INSERT INTO SCPT.SCP_TAB01_DATA(CF, NOME, COGNOME, SALARIO)
         VALUES (v_cf, v_nome, v_cognome, v_salario_num);
         v_count_valid := v_count_valid + 1;
      ELSE
         -- Inserisco negli scarti
         INSERT INTO SCPT.SCP_TAB01_SCARTI(ID_PK, CF, NOME, COGNOME, SALARIO, D_INS)
         VALUES (SEQ_ID_RUN.NEXTVAL, v_cf, v_nome, v_cognome, v_salario, SYSDATE);
         v_count_scarti := v_count_scarti + 1;
      END IF;

    EXCEPTION
      WHEN OTHERS THEN
        -- Se TO_NUMBER fallisce, inserisco negli scarti
        INSERT INTO SCPT.SCP_TAB01_SCARTI(ID_PK, CF, NOME, COGNOME, SALARIO, D_INS)
        VALUES (SEQ_ID_RUN.NEXTVAL, v_cf, v_nome, v_cognome, v_salario, SYSDATE);
        v_count_scarti := v_count_scarti + 1;
    END;

  END LOOP;

  CLOSE cur_ext;
  COMMIT;

  ----------------------------------------------------------
  -- Step 4: Log completamento
  ----------------------------------------------------------
  v_log_msg := 'Step 3 completato: ' || v_count_valid || ' record validi inseriti, ' 
               || v_count_scarti || ' record scartati';
  INSERT INTO SCPT.SCP_TAB_LOG(ID_LOG, DATA_LOG, STEP, LOG_MSG)
    VALUES (SEQ_ID_LOG.NEXTVAL, SYSDATE, 'Step 4', v_log_msg);
  COMMIT;

EXCEPTION
  WHEN OTHERS THEN
    v_log_msg := 'ERRORE: ' || SQLERRM;
    INSERT INTO SCPT.SCP_TAB_LOG(ID_LOG, DATA_LOG, STEP, LOG_MSG)
      VALUES (SEQ_ID_LOG.NEXTVAL, SYSDATE, 'ERRORE', v_log_msg);
    COMMIT;
    RAISE;

END LOAD_TO_TAB01;

/

create or replace PROCEDURE SCPT.LOAD_TO_TAB01_DINAMIC AS

  -- Variabili per log
  v_log_msg       VARCHAR2(4000);
  v_count_valid   NUMBER := 0;
  v_count_scarti  NUMBER := 0;
  v_stmt          CLOB;

BEGIN
  ----------------------------------------------------------
  -- Step 1: Log avvio
  ----------------------------------------------------------
  v_log_msg := 'Step 1: inizio caricamento dati da SCP_TAB_00_DATA';
  INSERT INTO SCPT.SCP_TAB_LOG(ID_LOG, DATA_LOG, STEP, LOG_MSG)
    VALUES (SEQ_ID_LOG.NEXTVAL, SYSDATE, 'Step 1', v_log_msg);
  COMMIT;

  ----------------------------------------------------------
  -- Step 2: Tronco solo tabella SCARTI
  ----------------------------------------------------------
  EXECUTE IMMEDIATE 'TRUNCATE TABLE SCPT.SCP_TAB01_SCARTI';
  EXECUTE IMMEDIATE 'TRUNCATE TABLE SCPT.SCP_TAB01_DATA';
  v_log_msg := 'Step 2: truncata SCP_TAB01_SCARTI e SCP_TAB01_DATA';
  INSERT INTO SCPT.SCP_TAB_LOG(ID_LOG, DATA_LOG, STEP, LOG_MSG)
    VALUES (SEQ_ID_LOG.NEXTVAL, SYSDATE, 'Step 2', v_log_msg);
  COMMIT;

  ----------------------------------------------------------
  -- Step 3: Inserimento record validi
  ----------------------------------------------------------
  v_stmt := q'[
        INSERT INTO SCPT.SCP_TAB01_DATA (CF, NOME, COGNOME, SALARIO)
        SELECT CF,
               NOME,
               COGNOME,
               TO_NUMBER(REPLACE(TRIM(SALARIO), ',', '.'), 
                         '9999999990.99', 
                         'NLS_NUMERIC_CHARACTERS = ''.,''')
        FROM SCPT.SCP_TAB00_DATA
        WHERE LENGTH(TRIM(CF)) <= 16
          AND REGEXP_LIKE(NOME, '^[[:alpha:][:space:]]+$')
          AND REGEXP_LIKE(COGNOME, '^[[:alpha:][:space:]]+$')
          AND SALARIO IS NOT NULL
          AND REGEXP_LIKE(TRIM(SALARIO), '^[0-9]+(\.[0-9]+)?$')
          AND TO_NUMBER(REPLACE(TRIM(SALARIO), ',', '.'), 
                        '9999999990.99', 
                        'NLS_NUMERIC_CHARACTERS = ''.,''') > 0
    ]';
      -- DBMS_OUTPUT.PUT_LINE(v_stmt); -- debug
  EXECUTE IMMEDIATE v_stmt;

  COMMIT;

  -- Conta validi
  v_stmt := 'SELECT COUNT(*) FROM SCPT.SCP_TAB01_DATA';
  EXECUTE IMMEDIATE v_stmt INTO v_count_valid;

  v_log_msg := 'Step 3: inseriti ' || v_count_valid || ' record validi';
  INSERT INTO SCPT.SCP_TAB_LOG(ID_LOG, DATA_LOG, STEP, LOG_MSG)
    VALUES (SEQ_ID_LOG.NEXTVAL, SYSDATE, 'Step 3', v_log_msg);
  COMMIT;

  ----------------------------------------------------------
  -- Step 4: Inserimento scarti
  ----------------------------------------------------------
  v_stmt := q'[
        INSERT INTO SCPT.SCP_TAB01_SCARTI (ID_PK, CF, NOME, COGNOME, SALARIO, D_INS)
        SELECT SEQ_ID_RUN.NEXTVAL,
               CF,
               NOME,
               COGNOME,
               SALARIO,
               SYSDATE
        FROM SCPT.SCP_TAB00_DATA
        WHERE NOT (
                  LENGTH(TRIM(CF)) <= 16
              AND REGEXP_LIKE(NOME, '^[[:alpha:][:space:]]+$')
              AND REGEXP_LIKE(COGNOME, '^[[:alpha:][:space:]]+$')
              AND SALARIO IS NOT NULL
              AND REGEXP_LIKE(TRIM(SALARIO), '^[0-9]+(\.[0-9]+)?$')
              AND TO_NUMBER(REPLACE(TRIM(SALARIO), ',', '.'), 
                            '9999999990.99', 
                            'NLS_NUMERIC_CHARACTERS = ''.,''') > 0
        )
    ]';
    -- DBMS_OUTPUT.PUT_LINE(v_stmt); -- debug
  EXECUTE IMMEDIATE v_stmt;
  

  COMMIT;

  -- Conta scarti
  v_stmt := 'SELECT COUNT(*) FROM SCPT.SCP_TAB01_SCARTI';
  EXECUTE IMMEDIATE v_stmt INTO v_count_scarti;

  v_log_msg := 'Step 4: inseriti ' || v_count_scarti || ' record scartati';
  INSERT INTO SCPT.SCP_TAB_LOG(ID_LOG, DATA_LOG, STEP, LOG_MSG)
    VALUES (SEQ_ID_LOG.NEXTVAL, SYSDATE, 'Step 4', v_log_msg);
  COMMIT;

EXCEPTION
  WHEN OTHERS THEN
    v_log_msg := 'ERRORE: ' || SQLERRM;
    INSERT INTO SCPT.SCP_TAB_LOG(ID_LOG, DATA_LOG, STEP, LOG_MSG)
      VALUES (SEQ_ID_LOG.NEXTVAL, SYSDATE, 'ERRORE', v_log_msg);
    COMMIT;
    --RAISE;

END LOAD_TO_TAB01_DINAMIC;

/

EXIT;

