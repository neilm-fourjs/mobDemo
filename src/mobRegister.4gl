IMPORT util

IMPORT FGL mobLib
IMPORT FGL dbLib
IMPORT FGL stdLib

CONSTANT C_REGVER = 4

&define DEBUG( l_lev, l_msg ) IF l_mobLib.cfg.debug THEN CALL stdLib.debugOut( l_lev, __FILE__, __LINE__, l_msg ) END IF

FUNCTION devreg_dummy()
	WHENEVER ERROR CALL app_error
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- check device is registered and connect to DB.
FUNCTION deviceRegister(l_mobLib mobLib INOUT) RETURNS BOOLEAN
	DEFINE l_pwd, l_userName STRING
	DEFINE l_id              STRING
	DEFINE l_ok              BOOLEAN

	IF NOT dbLib.connectDB(l_mobLib.dbName) THEN
		RETURN FALSE
	END IF
	LET l_mobLib.connected = TRUE

	IF isRegistered(l_mobLib) THEN -- already registered.
		RETURN TRUE
	END IF

	LET l_mobLib.reg.dev_ip =
			ARG_VAL(2) -- default is passed, if no value then mobRegister will try and calculate and set it.

	IF l_id IS NULL THEN
-- Get the device id / iccid / imei - All 3 fail on Android due to permissions.
		TRY
			CALL ui.Interface.frontCall("standard", "feinfo", "deviceId", [l_id])
		CATCH
		END TRY
		DEBUG(1, SFMT("deviceRegister: FEInfo deviceId: %1", l_id))
	END IF
	IF l_id IS NULL AND l_mobLib.feMobile THEN
		TRY
			CALL ui.Interface.frontCall("standard", "feinfo", "imei", [l_id])
		CATCH
		END TRY
		DEBUG(1, SFMT("deviceRegister: FEInfo imei: %1", l_id))
	END IF
	IF l_id IS NULL AND l_mobLib.feMobile THEN
		TRY
			CALL ui.Interface.frontCall("standard", "feinfo", "iccid", [l_id])
		CATCH
		END TRY
		DEBUG(1, SFMT("deviceRegister: FEInfo iccid: %1", l_id))
	END IF

	IF l_mobLib.feMobile THEN
		CALL l_mobLib.get_mobInfo()
	END IF

	IF l_mobLib.reg.dev_id IS NULL THEN
		LET l_mobLib.reg.dev_id = l_id
	END IF

	IF l_mobLib.reg.dev_id2 IS NULL THEN
		LET l_mobLib.reg.dev_id2 = generateId()
	END IF

	TRY -- can fail if the Android permissions are not correct!
		CALL ui.Interface.frontCall("standard", "feinfo", "ip", [l_mobLib.cli_ip])
		DEBUG(1, SFMT("deviceRegister: FEInfo IP: %1", l_mobLib.cli_ip))
	CATCH
	END TRY
	IF l_mobLib.cli_ip IS NULL THEN
		LET l_mobLib.cli_ip = fgl_getEnv("FGL_WEBSERVER_REMOTE_ADDR")
	END IF

	IF l_mobLib.reg.dev_id IS NULL THEN
		LET l_mobLib.reg.dev_id =
				SFMT("%1_%2%3%4@%5",
						l_mobLib.feName, l_mobLib.mobdev_info.model, l_mobLib.mobdev_info.os, l_mobLib.mobdev_info.osver,
						NVL(l_mobLib.cli_ip, "unknown"))
	END IF
	IF l_mobLib.reg.dev_id IS NULL THEN
		LET l_mobLib.reg.dev_id = generateId()
	END IF
	DEBUG(1, SFMT("deviceRegister: DeviceID: %1 Login timeout: %2", l_mobLib.reg.dev_id, l_mobLib.cfg.timeouts.login))
	IF l_mobLib.reg.dev_id IS NULL THEN
		CALL stdLib.error("No Device ID!", TRUE)
		RETURN FALSE
	END IF

-- register a new device
	OPEN FORM mobRegistered FROM l_mobLib.openForm("mobRegister")
	DISPLAY FORM mobRegistered
	DISPLAY "Application Registration" TO titl

	CALL stdLib.warning(SFMT("Device not registared\nApplication:'%1'", l_mobLib.appName), TRUE)

	LET l_mobLib.reg.regVersion = C_REGVER
	INPUT BY NAME l_mobLib.reg.dev_id2, l_mobLib.reg.cono, l_mobLib.user_id, l_pwd WITHOUT DEFAULTS
		BEFORE INPUT
			IF l_mobLib.reg.cono IS NOT NULL THEN
				CALL DIALOG.setFieldActive("cono", FALSE)
			END IF
		BEFORE FIELD cono
			DISPLAY "Please enter a valid company number." TO formhelp

		BEFORE FIELD user_id
			DISPLAY "Please enter a valid login id to register m_mobLib device." TO formhelp

		BEFORE FIELD l_pwd
			DISPLAY "Please enter your password." TO formhelp

		ON ACTION about
			CALL l_mobLib.about()

		ON IDLE l_mobLib.cfg.timeouts.login
			CALL l_mobLib.timeout("deviceRegister")

		ON ACTION enterbackground
			CALL l_mobLib.exitProgram("register - enterbackground", 0)

	END INPUT
	IF int_flag THEN
		RETURN FALSE
	END IF

	LET l_mobLib.user_id = l_mobLib.user_id CLIPPED, l_mobLib.reg.cono
	CALL dbLib.validUser(l_mobLib.user_id, l_pwd) RETURNING l_ok, l_userName
	IF NOT l_ok THEN
		CALL dbLib_error("Invalid login details.")
		RETURN FALSE
	END IF

	IF NOT dbLib.checkTable("mobdemoreg") THEN
		RETURN FALSE
	END IF

-- Register App
	LET l_mobLib.reg.when = CURRENT
	LET l_mobLib.regData  = util.JSON.stringify(l_mobLib.reg)
	CALL ui.Interface.frontCall("localStorage", "setItem", [l_mobLib.appName, l_mobLib.regData], [])

	IF NOT dbLib.execute(
			SFMT("INSERT INTO mobdemoreg VALUES('%1','%2','%3','%4','%5', '%6')",
					l_mobLib.appName, l_mobLib.reg.dev_id, l_mobLib.cli_ip, l_mobLib.reg.cono, l_mobLib.user_id,
					l_mobLib.reg.when)) THEN
		RETURN FALSE
	END IF

	DEBUG(0, SFMT("deviceRegister: %1", util.json.stringify(l_mobLib)))

	RETURN TRUE
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Checks if the device is registered
FUNCTION isRegistered(l_mobLib mobLib INOUT) RETURNS BOOLEAN

	CALL ui.Interface.frontCall("localStorage", "getItem", [l_mobLib.appName], [l_mobLib.regData])
	IF l_mobLib.regData IS NULL THEN
		RETURN FALSE
	END IF
	TRY
		CALL util.JSON.parse(l_mobLib.regData, l_mobLib.reg)
		DEBUG(2, "isRegistered: Got reg data from localStorage")
	CATCH
		CALL stdLib.error(SFMT("Failed to parse reg data '%1'", l_mobLib.appName), TRUE)
		RETURN FALSE
	END TRY

	IF l_mobLib.reg.regVersion IS NULL OR l_mobLib.reg.regVersion != C_REGVER THEN
		LET l_mobLib.regData = NULL
		CALL ui.Interface.frontCall("localStorage", "setItem", [l_mobLib.appName, l_mobLib.regData], [])
		CALL stdLib.popup("Warning", "Device Registration Version changed.", "exclamtion", 10)
		CALL l_mobLib.exitProgram("Device Registration Version changed.", 1)
	END IF

	DEBUG(1, SFMT("isRegistered: dev_id: %1", l_mobLib.reg.dev_id))

	RETURN TRUE
END FUNCTION
