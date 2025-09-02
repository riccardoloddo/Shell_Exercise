-- STEP viene passato come argomento da SQL*Plus (&1)
DECLARE
    v_step VARCHAR2(20) := '&1';
BEGIN
    IF v_step = 'PRELOAD' THEN
        -- Provo a droppare la tabella se esiste
        BEGIN
            EXECUTE IMMEDIATE 'DROP TABLE SCPT.SCP_TAB00_DATA CASCADE CONSTRAINTS';
        EXCEPTION
            WHEN OTHERS THEN
                IF SQLCODE != -942 THEN  -- -942 = table does not exist
                    RAISE;
                END IF;
        END;

        -- Creo la tabella da zero
        EXECUTE IMMEDIATE '
            CREATE TABLE SCPT.SCP_TAB00_DATA (
                CF VARCHAR2(100 BYTE), 
                NOME VARCHAR2(100 BYTE),
                COGNOME VARCHAR2(100 BYTE),
                SALARIO VARCHAR2(100 BYTE)
            )';
    ELSIF v_step = 'POSTLOAD' THEN
        -- Eseguo la procedura per popolare tabella 01
        SCPT.LOAD_TO_TAB01_DINAMIC;
    END IF;
END;
/
EXIT;
