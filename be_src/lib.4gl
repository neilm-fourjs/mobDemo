IMPORT os
IMPORT FGL fgldialog

PUBLIC DEFINE m_debug_lev SMALLINT
PUBLIC DEFINE m_mdi       BOOLEAN = FALSE
DEFINE m_log_file         STRING
DEFINE m_log              base.Channel

FUNCTION db_connect()
	DEFINE l_db STRING

	LET l_db = fgl_getenv("DBNAME")
	IF l_db.getLength() < 1 THEN
		LET l_db = "mobdemo"
	END IF

	IF NOT os.Path.exists(l_db) THEN
		IF base.Application.getProgramName() != "mk_db" THEN
			RUN SFMT("fglrun mk_db %1", l_db)
		ELSE
			CALL showError(SFMT("Database doesnt exist %1", l_db))
			EXIT PROGRAM
		END IF
	END IF

	TRY
		CONNECT TO l_db || "+driver='dbmpgs'"
	CATCH
		CALL showError(SQLERRMESSAGE)
		EXIT PROGRAM
	END TRY
	CALL log(1, SFMT("Connected to %1", l_db))
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Show an error message and log that message.
FUNCTION showError(l_err STRING) RETURNS()
	CALL log(0, l_err)
	CALL fgldialog.fgl_winMessage("Error", l_err, "exclamation")
END FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION exit_program(l_stat SMALLINT, l_msg STRING)
	CALL log(0, l_msg)
	IF m_log IS NOT NULL THEN
		CALL m_log.close()
	END IF
	EXIT PROGRAM l_stat
END FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION log(l_lev SMALLINT, l_msg STRING)
	IF m_log IS NULL THEN
		LET m_log_file = os.Path.join("..", "logs")
		IF NOT os.Path.exists(m_log_file) THEN
			IF NOT os.Path.mkdir(m_log_file) THEN
				CALL fgldialog.fgl_winMessage("Error", SFMT("Failed to mkdir %1", m_log_file), "exclamation")
				LET m_log_file = "." -- fall back to current dir!
			END IF
		END IF
		LET m_log_file = os.Path.join(m_log_file, SFMT("%1.log", base.Application.getProgramName()))
		LET m_log      = base.Channel.create()
		CALL m_log.openFile(m_log_file, "a+")
	END IF
	LET l_msg = SFMT("%1: %2", CURRENT, l_msg)
	IF m_debug_lev >= l_lev THEN
		CALL m_log.writeLine(l_msg)
		DISPLAY SFMT("%1:%2", base.Application.getProgramName(), l_msg)
	END IF
END FUNCTION
