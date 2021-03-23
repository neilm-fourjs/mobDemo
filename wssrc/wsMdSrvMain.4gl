-- This program registers the services.

IMPORT com

IMPORT FGL ws_lib
IMPORT FGL debug
IMPORT FGL wsMdSrv

CONSTANT C_VER = "1.00"

MAIN
	DEFINE l_db STRING

	LET l_db = fgl_getResource("my.dbname")
	CALL debug.output(SFMT("Service '%1' version '%2' starting ...", base.Application.getProgramName(), C_VER), FALSE)
	TRY
		CALL debug.output(SFMT("Connecting to '%1' ...", l_db), FALSE)
		CONNECT TO l_db
		CALL debug.output(SFMT("DB Connect to '%1' okay", l_db), FALSE)
	CATCH
		CALL debug.output(SFMT("DB Connect to '%1' failed: %2", l_db, SQLERRMESSAGE), FALSE)
		EXIT PROGRAM 1
	END TRY

	IF NOT wsMdSrv.checkTable("trimservers") THEN
		EXIT PROGRAM 1
	END IF

	CALL debug.output("Listening ...", FALSE)
	CALL com.WebServiceEngine.RegisterRestService("wsMdSrv", "mdsrv")
	CALL com.WebServiceEngine.Start()
	WHILE ws_lib.ws_ProcessServices_stat(com.WebServiceEngine.ProcessServices(-1))
	END WHILE
	CALL debug.output("Server stopped", FALSE)
END MAIN
--------------------------------------------------------------------------------------------------------------