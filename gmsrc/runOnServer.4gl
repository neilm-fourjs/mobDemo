{
This program is designed to run a program from another server by requesting the url from a web service based on an 'api' value.
If run in GDC - it uses 'execute' to run: gdc -u <url>
If run in GWC - it uses 'launchURL' ro run the <url>
If run in GMA/GMI - it uses 'runOnServer' to run the <url>

Initial designed from for running on mobile where the target application url can change depending on the
IP address of the device requesting to run it.
The WS looks up the url in a table based on the 'api' and 'ip' of the device making the request.

The default url information for the web service comes from the fglprofile, ie:
my.ws.server = "generodemos.dynu.net"
my.ws.gasalias = "z"
my.ws.wsxcf = "wsrun"
my.ws.wsapp = "runServ"
my.ws.wsapi = "myapi"

The returned url and database name are saved in a config file ( C_CFG_FILE )
If the config file already exists then url is read from that instead of calling the web service.

Arg1: <api> - this overrides the config file and does the WS call with the specified <api> value and runs that.
              NOTE: This does NOT save this new url to the config.
}

IMPORT os
IMPORT util
IMPORT FGL fgldialog
IMPORT FGL mdsrv

CONSTANT C_ROS_VER   = 3
CONSTANT C_CFG_FILE  = "mobDemo.cfg"
CONSTANT C_LOG_FILE  = "mobDemo.log"
CONSTANT C_GRACETIME = 6 -- if runOnServer takes longer than this to fail it probably worked and timeout in the app.

DEFINE m_cfg_ver SMALLINT

DEFINE m_cfg RECORD
	version  SMALLINT,
	secure   BOOLEAN,
	server   STRING,
	gasalias STRING,
	ws_xcf   STRING,
	ws_app   STRING,
	ws_url   STRING, -- URL for the WS server
	ws_rep   v1_getURLResponseBodyType
END RECORD
DEFINE m_isMobile BOOLEAN = FALSE
DEFINE m_cfgPath  STRING
DEFINE m_logFile  STRING
DEFINE m_log      STRING
MAIN
	DEFINE l_res    STRING
	DEFINE l_cli    STRING
	DEFINE l_feCall STRING
	DEFINE l_feMod  STRING
	DEFINE l_stat   SMALLINT
	DEFINE l_st     DATETIME YEAR TO SECOND
	DEFINE l_msg    STRING

	LET l_cli    = ui.interface.getFrontEndName() || " " || ui.Interface.getFrontEndVersion()
	LET l_feMod  = "standard"
	LET l_feCall = "launchURL"
	IF l_cli.subString(1, 2) = "GM" THEN
		LET m_isMobile = TRUE
		LET l_feMod    = "mobile"
		LET l_feCall   = "runOnServer"
	END IF
	LET m_cfg_ver = fgl_getResource("config.version")
	CALL logIt(SFMT("Client: %1 isMobile: %2 Config Ver: %3", l_cli, m_isMobile, m_cfg_ver))
	CALL logIt(SFMT("FGLPROFILE: %1", fgl_getEnv("FGLPROFILE")))

	CALL getCFGPath()

	IF m_isMobile THEN
		CALL ui.Interface.frontCall("mobile", "connectivity", [], l_res)
		CALL logIt(SFMT("connectivity res: %1", l_res))
		IF l_res = "NONE" THEN
			CALL fgldialog.fgl_winMessage("Error", "No network detected, check your wifi settings", "exclamation")
			CALL exitProgram(1)
		END IF
	END IF

	IF NOT loadCFG() THEN
		CALL logIt(SFMT("Def URI: %1", mdsrv.Endpoint.Address.Uri))
		LET mdsrv.Endpoint.Address.Uri = m_cfg.ws_url
		CALL logIt(SFMT("New URI: %1", mdsrv.Endpoint.Address.Uri))
-- Call the WS to get the URL for the Application
		CALL mdsrv.v1_getURL(m_cfg.ws_rep.api) RETURNING l_stat, m_cfg.ws_rep.*
		IF l_stat != 0 THEN
			LET l_msg = SFMT("Failed to get URL Stat: %1 from\n%2\n%3 %4", l_stat, m_cfg.ws_url, SQLCA.sqlcode, SQLCA.sqlerrm)
			CALL logIt(l_msg)
			CALL fgl_winMessage("Error", l_msg, "exclamation")
			CALL exitProgram(1)
		END IF
		CALL logIt(SFMT("WS Result: %1", m_cfg.ws_rep.info))
	END IF

	IF m_cfg.ws_rep.dbname.getLength() < 1 THEN
		LET m_cfg.ws_rep.dbname = "xxxx"
	END IF
	IF m_cfg.ws_rep.ip.getLength() < 1 THEN
		LET m_cfg.ws_rep.ip = "unknown"
	END IF

	IF m_cfg.ws_rep.url IS NULL OR m_cfg.ws_rep.url.getLength() < 2 THEN
		CALL fgldialog.fgl_winMessage("Error", SFMT("Invalid App URL: %1", m_cfg.ws_rep.url), "exclamation")
		CALL exitProgram(1)
	END IF
	LET m_cfg.ws_rep.url =
			m_cfg.ws_rep.url.append(SFMT("?Arg=%1&Arg=%2&Arg=%3", m_cfg.ws_rep.dbname, m_cfg.ws_rep.ip, C_ROS_VER))
	TRY
		LET l_st  = CURRENT
		LET l_res = "failed"
		IF l_cli.subString(1, 3) = "GDC" THEN
			LET l_feCall         = "execute"
			LET m_cfg.ws_rep.url = "gdc -u " || m_cfg.ws_rep.url
		END IF
		CALL logIt(SFMT("%1:%2 Url: %3", l_feMod, l_feCall, m_cfg.ws_rep.url))
		IF l_cli.subString(1, 3) = "GDC" THEN
			CALL ui.Interface.frontCAll(l_feMod, l_feCall, [m_cfg.ws_rep.url, TRUE], [l_res])
			IF l_res = 1 THEN
				LET l_res = "ok"
			END IF
		ELSE
			CALL ui.Interface.frontCAll(l_feMod, l_feCall, [m_cfg.ws_rep.url], [l_res])
		END IF
	CATCH
		IF (l_st + C_GRACETIME UNITS MINUTE) > CURRENT THEN
			LET l_msg = SFMT("Error:%1\n\nURL: %2\nRes: %3", err_get(STATUS), m_cfg.ws_rep.url, l_res)
			CALL logIt(l_msg)
			CALL fgldialog.fgl_winMessage("Error", l_msg, "exclamation")
			CALL exitProgram(1)
		ELSE
			CALL logIt(SFMT("Failed, Result: %1 but took longer than %2 minutes", l_res, C_GRACETIME))
			CALL exitProgram(0)
		END IF
		--CALL ui.Interface.frontCAll("standard", "launchUrl", [m_cfg.app_url], [l_res])
	END TRY
	CALL logIt(SFMT("Result: %1", l_res))
	IF l_res != "ok" THEN
		CALL fgldialog.fgl_winMessage("Done", SFMT("Done\nURL: %1\nRes: %2", m_cfg.ws_rep.url, l_res), "exclamation")
	END IF
	CALL exitProgram(0)
END MAIN
--------------------------------------------------------------------------------------------------------------
FUNCTION getCFGPath() RETURNS()

-- Get Permission for reading/writing the config file.
	IF m_isMobile THEN
		CALL setPermission("READ_PRIVILEGED_PHONE_STATE")
		CALL setPermission("READ_EXTERNAL_STORAGE")
		CALL setPermission("WRITE_EXTERNAL_STORAGE")
		CALL setPermission("MANAGE_EXTERNAL_STORAGE")
		CALL setPermission("ACCESS_MEDIA_LOCATION")
		CALL setPermission("ACCESS_CAMERA")
	END IF

	CASE -- find the Downloads folder.
		WHEN os.path.exists("/storage/sdcard0/download")
			LET m_cfgPath = "/storage/sdcard0/download"
		WHEN os.path.exists("/sdcard/Download")
			LET m_cfgPath = "/sdcard/Download"
		WHEN os.path.exists("/storage/emulated/Download")
			LET m_cfgPath = "/storage/emulated/Download"
	END CASE
	IF m_cfgPath IS NULL THEN
		CALL fgldialog.fgl_winMessage("Error", "Can't find the Download folder", "exclamation")
		CALL exitProgram(1)
	END IF
	LET m_logFile = os.path.join(m_cfgPath, C_LOG_FILE)
	LET m_cfgPath = os.path.join(m_cfgPath, C_CFG_FILE)
END FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION saveCFG() RETURNS()
	DEFINE l_json TEXT

	CALL logIt(SFMT("Saving config to '%1' ", m_cfgPath))
	TRY
		LOCATE l_json IN FILE m_cfgPath
		LET l_json = util.JSON.stringify(m_cfg)
	CATCH
		CALL logIt(SFMT("Saving config to '%1' failed %2", m_cfgPath, STATUS))
		CALL fgldialog.fgl_winMessage("Error", SFMT("Failed to save %1", m_cfgPath), "exclamation")
	END TRY

END FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION loadCFG() RETURNS BOOLEAN
	DEFINE l_json     TEXT
	DEFINE l_useCfg   BOOLEAN = FALSE
	DEFINE l_ret      BOOLEAN = FALSE
	DEFINE l_forceAPI STRING

	LET l_forceAPI = ARG_VAL(1)

	IF os.path.exists(m_cfgPath) AND l_forceAPI.getLength() < 2 THEN
		CALL logIt(SFMT("Loading config from '%1' ", m_cfgPath))
		LOCATE l_json IN FILE m_cfgPath
		TRY
			CALL util.JSON.parse(l_json, m_cfg)
			LET l_ret = TRUE
			IF m_cfg.ws_url IS NULL OR m_cfg.ws_url.getLength() < 2 THEN
				LET m_cfg.ws_url =
						SFMT("%1://%2/%3/ws/r/%4/%5",
								IIF(m_cfg.secure, "https", "http"), m_cfg.server, m_cfg.gasalias, m_cfg.ws_xcf, m_cfg.ws_app)
			END IF
			LET l_useCFG = TRUE
		CATCH
			CALL fgldialog.fgl_winMessage("Error", SFMT("Failed to parse JSON from %1", m_cfgPath), "exclamation")
			CALL logIt(SFMT("Failed to parse JSON from %1", m_cfgPath))
			CALL logIt(SFMT("JSON: %1", l_json))
			LET l_useCfg = FALSE
		END TRY
		IF m_cfg.version IS NULL THEN
			LET m_cfg.version = 0
		END IF
		IF m_cfg.version != m_cfg_ver THEN
			CALL logIt("Config wrong version, forcing defaults")
		END IF
	ELSE
		CALL logIt(SFMT("No config in '%1' ", m_cfgPath))
	END IF

	IF NOT l_useCfg THEN
		LET m_cfg.version  = m_cfg_ver
		LET m_cfg.secure   = TRUE
		LET m_cfg.server   = fgl_getResource("my.ws.server")
		LET m_cfg.gasalias = fgl_getResource("my.ws.gasalias")
		LET m_cfg.ws_xcf   = fgl_getResource("my.ws.wsxcf")
		LET m_cfg.ws_app   = fgl_getResource("my.ws.wsapp")
		LET m_cfg.ws_url =
				SFMT("%1://%2/%3/ws/r/%4/%5",
						IIF(m_cfg.secure, "https", "http"), m_cfg.server, m_cfg.gasalias, m_cfg.ws_xcf, m_cfg.ws_app)
		LET m_cfg.ws_rep.api = fgl_getResource("my.ws.wsapi")
		IF l_forceAPI.getLength() > 1 THEN
			LET m_cfg.ws_rep.api = l_forceAPI
		ELSE
			CALL logIt("Config set from fglprofile values.")
			CALL saveCFG()
		END IF
	END IF

	IF m_cfg.ws_rep.url IS NULL OR m_cfg.ws_rep.url.getLength() < 2 THEN
		LET l_ret = FALSE
	END IF

	CALL logIt(SFMT("WS URL: %1", m_cfg.ws_url))
	CALL logIt(SFMT("AP URL: %1", m_cfg.ws_rep.url))

	RETURN l_ret
END FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION setPermission(l_perm STRING) RETURNS()
	DEFINE l_result STRING
	LET l_result = SFMT("android.permission.%1", l_perm)
	CALL logIt(SFMT("Ask for: %1", l_result))
	TRY
		CALL ui.Interface.frontCall("android", "askForPermission", [l_result], [l_result])
		CALL logIt(SFMT("Result of ask for %1: %2", l_perm, l_result))
	CATCH
		CALL logIt(SFMT("Failed %1: %2", STATUS, ERR_GET(STATUS)))
	END TRY
END FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION logIt(l_mess STRING) RETURNS()
	LET l_mess = CURRENT, ":", l_mess
	DISPLAY l_mess
	LET m_log = m_log.append(l_mess || "\n")
END FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION exitProgram(l_stat SMALLINT) RETURNS()
	DEFINE c base.Channel
	IF m_logFile IS NOT NULL THEN
		LET c = base.Channel.create()
		TRY
			CALL c.openFile(m_logFile, "w+")
			CALL c.writeLine(m_log)
			CALL c.close()
			DISPLAY "Log written to: ", m_logFile
		CATCH
			CALL logIt(SFMT("Failed to write log '%1' %2:%3", m_logFile, STATUS, ERR_GET(STATUS)))
			CALL fgldialog.fgl_winMessage("Error", m_log, "exclamation")
		END TRY
	END IF
	EXIT PROGRAM l_stat
END FUNCTION
