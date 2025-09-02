drop table SCP_TAB00_DATA;

CREATE TABLE SCPT.SCP_TAB00_DATA 
   (	CF VARCHAR2(100 BYTE), 
	NOME VARCHAR2(100 BYTE),
	COGNOME VARCHAR2(100 BYTE),
	SALARIO VARCHAR2(100 BYTE)
) ;


CREATE OR REPLACE PROCEDURE import_data (file_name IN VARCHAR2)
IS
  F   UTL_FILE.FILE_TYPE;
  REC VARCHAR2(2000);
BEGIN
  -- Pulizia tabella
  DELETE FROM SCP_TAB00_DATA;

  F := UTL_FILE.FOPEN('SCP_DATA_DIR', file_name, 'R');

  IF UTL_FILE.IS_OPEN(F) THEN
    -- SALTA LA PRIMA RIGA (header)
    BEGIN
      utl_file.get_line(F, REC);
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        NULL; -- se il file è vuoto
    END;

    LOOP
      BEGIN
        utl_file.get_line(F, REC);
        EXIT WHEN REC IS NULL;

        INSERT INTO SCP_TAB00_DATA (CF, NOME, COGNOME, SALARIO) VALUES (
          REGEXP_SUBSTR(REC, '[^;]+', 1, 1),
          REGEXP_SUBSTR(REC, '[^;]+', 1, 2),
          REGEXP_SUBSTR(REC, '[^;]+', 1, 3),
          REGEXP_SUBSTR(REC, '[^;]+', 1, 4)
        );

      EXCEPTION
        WHEN NO_DATA_FOUND THEN
          EXIT;
      END;
    END LOOP;

    -- Commit finale
    COMMIT;

    UTL_FILE.FCLOSE(F);
  END IF;
END import_data;
/

EXECUTE import_data('dati.csv')

EXECUTE LOAD_TO_TAB01_DINAMIC;

EXIT;