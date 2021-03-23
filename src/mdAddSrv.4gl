IMPORT util
IMPORT FGL mdsrv
IMPORT FGL fgldialog


MAIN
	DEFINE l_ret  SMALLINT
	DEFINE l_stat BOOLEAN
	DEFINE l_api  VARCHAR(30)
	DEFINE l_ip STRING
	DEFINE l_rec v1_getURLResponseBodyType
	DEFINE l_ver v1_getVerResponseBodyType
	DEFINE l_list v1_getListResponseBodyType

	IF NOT unlock() THEN
		EXIT PROGRAM
	END IF

	OPEN FORM f FROM "mdAddSrv"
	DISPLAY FORM f

	CALL mdsrv.v1_getVer() RETURNING l_ret, l_ver.*
	DISPLAY BY NAME l_ver.*

	DISPLAY mdsrv.Endpoint.Address.Uri TO server

	WHILE NOT int_flag
		INPUT BY NAME l_rec.* ATTRIBUTES(WITHOUT DEFAULTS, UNBUFFERED)
			BEFORE FIELD api
				CALL DIALOG.setActionActive("accept", FALSE)
				CALL DIALOG.setActionActive("delete", FALSE)
			AFTER FIELD api
				LET l_api = l_rec.api
				CALL mdsrv.v1_getList(l_rec.api) RETURNING l_ret, l_list
				CALL popup_combo( ui.ComboBox.forName("formonly.ip"), l_list )
				
				CALL mdsrv.v1_getURL(l_rec.api) RETURNING l_ret, l_rec.*
				DISPLAY "USing: ", mdsrv.Endpoint.Address.Uri
				DISPLAY "Failed: ", mdsrv.mySetFailed.message
				IF l_ret != 0 THEN
					CALL fgldialog.fgl_winMessage(
							"Result", SFMT("get returned: %1\nMessage: %2", l_ret, mdsrv.myNotFound.message), "information")
					LET l_rec.api = l_api
				ELSE
					CALL DIALOG.setActionActive("delete", TRUE)
					CALL DIALOG.setActionActive("accept", TRUE)
				END IF

			ON ACTION exit
				LET int_flag = TRUE
				EXIT INPUT

			ON ACTION add
				LET int_flag = FALSE
				INPUT BY NAME l_ip
				IF NOT int_flag THEN
					LET l_list[ l_list.getLength() + 1 ] = l_ip
					CALL popup_combo( ui.ComboBox.forName("formonly.ip"), l_list )
					LET l_rec.ip = l_ip
				END IF
				
			ON ACTION delete
				CALL DIALOG.setActionActive("delete", FALSE)
				CALL mdsrv.v1_delURL(l_rec.api, l_rec.ip) RETURNING l_ret, l_stat
				CALL fgldialog.fgl_winMessage(
						"Result", SFMT("del returned: %1\nStat: %2\nMessage: %3", l_ret, l_stat, mdsrv.myNotFound.message),
						"information")
		END INPUT
		IF NOT int_flag THEN
			CALL mdsrv.v1_setURL(l_rec.*) RETURNING l_ret, l_stat
			CALL fgldialog.fgl_winMessage(
					"Result", SFMT("set returned: %1\nStat: %2\nMessage: %3", l_ret, l_stat, mdsrv.mySetFailed.message),
					"information")
		END IF
	END WHILE

END MAIN
--------------------------------------------------------------------------------------------------------------
-- simple pass code: minutes and date + day: 33min on a friday(5) the 5th = 3310
FUNCTION unlock() RETURNS BOOLEAN
	DEFINE d,m,x SMALLINT
	DEFINE c4 CHAR(4)
	DEFINE l_dt DATETIME YEAR TO MINUTE
	LET l_dt = CURRENT
	LET d = util.datetime.format( l_dt, "%d" )
	LET m = util.datetime.format( l_dt, "%M" )
	LET x = (m*100) + d + WEEKDAY( TODAY )
	DISPLAY SFMT("D: %1 M: %2 W: %3 X: %4", d, m, WEEKDAY( TODAY ), x )
	PROMPT "Enter pass code? " FOR c4 ATTRIBUTE(INVISIBLE)
	IF x = c4 THEN RETURN TRUE END IF
	RETURN FALSE
EnD FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION popup_combo( l_cb ui.ComboBox, l_list v1_getListResponseBodyType )
	DEFINE x SMALLINT
	CALL l_cb.clear()
	FOR x = 1 TO l_list.getLength()
		CALL l_cb.addItem(l_list[x], l_list[x])
	END FOR
EnD FUNCTION