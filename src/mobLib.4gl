IMPORT util
IMPORT os

IMPORT FGL fgldialog
IMPORT FGL stdLib

&include "schema.inc"

&define DEBUG( l_lev, l_msg ) IF this.cfg.debug THEN CALL stdLib.debugOut( l_lev, __FILE__, __LINE__, l_msg ) END IF

CONSTANT C_DEF_DB = "mobdemo"
CONSTANT C_CFGVER = 4

GLOBALS
	DEFINE g_appVersion STRING
END GLOBALS

PUBLIC TYPE mobLibCFG RECORD
	useCFG       BOOLEAN,
	cfgVersion   SMALLINT,
	debug        SMALLINT,
	fileStorage  STRING,
	cfgPath      STRING,
	imgPath      STRING,
	docPath      STRING,
	logPath      STRING,
	baseDir      STRING,
	iconMenu     BOOLEAN,
	refreshAge   DATETIME HOUR TO MINUTE,
	jobAge       SMALLINT,
	allowTest    BOOLEAN,
	style        SMALLINT,
	gma_settings BOOLEAN,
	timeouts RECORD
		login   SMALLINT,
		confirm SMALLINT,
		menu    SMALLINT,
		short   SMALLINT,
		medium  SMALLINT,
		long    SMALLINT
	END RECORD
END RECORD

TYPE t_mobInfo RECORD
	connected STRING,
	ip        STRING,
	model     STRING,
	os        STRING,
	osver     STRING,
	datadir   STRING
END RECORD

PUBLIC TYPE mobLib RECORD
	reg RECORD
		regVersion SMALLINT,
		dev_id     VARCHAR(40),
		dev_id2    VARCHAR(40),
		dev_ip     VARCHAR(80),
		cono       CHAR(4),
		when       DATETIME YEAR TO SECOND
	END RECORD,
	user_id       LIKE emp01.user_id,
	emp_code      LIKE emp01.short_code,
	branch        LIKE bra01.branch_code,
	appName       STRING,
	regFile       STRING,
	regData       STRING,
	dbName        STRING,
	connected     BOOLEAN,
	feName        STRING,
	feVer         STRING,
	feMobile      BOOLEAN,
	cli_ip        STRING,
	sysName       STRING,
	ros_ver       SMALLINT,
	mobdev_info   t_mobInfo,
	eclipseGenVer CHAR(3),
	cloudStore    BOOLEAN,
	viewFiles     BOOLEAN,
	cfg           mobLibCFG,
	lastError     STRING,
	buttons DYNAMIC ARRAY OF RECORD
		name    STRING,
		text    STRING,
		img     STRING,
		enabled BOOLEAN
	END RECORD
END RECORD

FUNCTION (this mobLib) init(l_app STRING) RETURNS(mobLib)
	DEFINE x SMALLINT
	WHENEVER ERROR CALL app_error
	LET this.cfg.debug = fgl_getEnv("MDDEBUG")
	LET this.appName   = l_app.trim()

-- Setup database / company no
	LET this.dbName = ARG_VAL(1)
	IF this.dbName IS NULL THEN
		LET this.dbName = C_DEF_DB
	END IF
	LET this.ros_ver = ARG_VAL(3)
	IF this.ros_ver IS NULL THEN
		LET this.ros_ver = 0
	END IF

	IF this.dbName.getCharAt(1) = "d" THEN
		LET this.reg.cono = this.dbName.subString(2, 5)
	ELSE
		LET this.reg.cono = "9999"
	END IF

	LET this.cli_ip = fgl_getEnv("FGL_WEBSERVER_REMOTE_ADDR")

-- Setup default configuration.
	LET this.cfg.cfgVersion       = C_CFGVER
	LET this.cfg.useCFG           = fgl_getEnv("USECFG")
	LET this.cfg.fileStorage      = fgl_getEnv("FILESTORAGE")
	LET this.cfg.cfgPath          = fgl_getEnv("MDCFGPATH")
	LET this.cfg.imgPath          = fgl_getEnv("MDIMGPATH")
	LET this.cfg.docPath          = fgl_getEnv("MDDOCPATH")
	LET this.cfg.logPath          = fgl_getEnv("MDLOGPATH")
	LET this.cfg.baseDir          = fgl_getEnv("BASEDIR")
	LET this.cfg.iconMenu         = fgl_getEnv("ICONMENU")
	LET this.cfg.style            = fgl_getEnv("STYLE")
	LET this.cfg.gma_settings     = fgl_getEnv("GMASETTINGS")
	LET this.cfg.timeouts.confirm = 60
	LET this.cfg.timeouts.login   = 600
	LET this.cfg.timeouts.menu    = 300
	LET this.cfg.timeouts.short   = 300
	LET this.cfg.timeouts.medium  = 600
	LET this.cfg.timeouts.long    = 1200
	LET this.cfg.refreshAge       = "00:15"
	LET this.cfg.jobAge           = 120
	LET this.cfg.allowTest        = TRUE
	IF this.cfg.style IS NULL THEN
		LET this.cfg.style = 0
	END IF

-- Initialize the file storage location - used for logs and images etc
	IF NOT stdLib.mkDir(this.cfg.fileStorage) THEN
		CALL this.exitProgram(SFMT("setup failed: %1 ", stdLib.m_lastError), 1)
	END IF

-- Initialize the file storage location - used for logs and images etc
	LET this.cfg.fileStorage = os.path.join(this.cfg.fileStorage, this.reg.cono)
	IF NOT stdLib.mkDir(this.cfg.fileStorage) THEN
		CALL this.exitProgram(SFMT("setup failed: %1 ", stdLib.m_lastError), 1)
	END IF

-- Setup the cfg file path
	LET this.cfg.cfgPath = os.path.join(this.cfg.fileStorage, this.cfg.cfgPath)
	IF NOT stdLib.mkDir(this.cfg.cfgPath) THEN
		CALL this.exitProgram(SFMT("setup failed: %1 ", stdLib.m_lastError), 1)
	END IF
	LET stdLib.m_logPath = this.cfg.cfgPath
	CALL this.getConfig()

	IF this.cfg.baseDir IS NULL THEN
		CALL stdLib.error("BASEDIR is not set!", TRUE)
		CALL this.exitProgram(SFMT("setup failed: %1 ", stdLib.m_lastError), 1)
	END IF

	LET stdLib.m_debug = this.cfg.debug

-- Setup the log file path
	LET this.cfg.logPath = os.path.join(this.cfg.fileStorage, this.cfg.logPath)
	IF NOT stdLib.mkDir(this.cfg.logPath) THEN
		CALL this.exitProgram(SFMT("setup failed: %1 ", stdLib.m_lastError), 1)
	END IF
	LET stdLib.m_logPath = this.cfg.logPath
	DEBUG(1, SFMT("PWD: %1", os.path.pwd()))
	IF this.cfg.debug > 0 THEN
		DEBUG(1, SFMT("Debug enabled: %1", this.cfg.debug))
		DEBUG(2, SFMT("Args: %1", NUM_ARGS()))
		FOR x = 1 TO NUM_ARGS()
			DEBUG(2, SFMT("Arg: %1 = %2", x, ARG_VAL(x)))
		END FOR
	END IF
	DEBUG(0, SFMT("CFG Path: '%1'", this.cfg.cfgPath))

	IF NUM_ARGS() = 0 THEN
		DEBUG(0, SFMT("WARNING: using default database '%1'", this.dbName))
	END IF

	LET this.regFile  = this.appName || ".reg"
	DEBUG(1, "Doing getFrontEndName ...")
	LET this.feName   = ui.Interface.getFrontEndName()
	LET this.feMobile = FALSE
	DEBUG(1, SFMT("Done getFrontEndName %1", this.feName))
	DEBUG(1, "Doing getFrontEndVersion ...")
	LET this.feVer   = ui.Interface.getFrontEndVErsion()
	DEBUG(1, SFMT("Done getFrontEndVersion %1", this.feVer))

-- Setup image storage on the server.
	LET this.cfg.imgPath = os.path.join(this.cfg.fileStorage, this.cfg.imgPath)
	IF NOT stdLib.mkDir(this.cfg.imgPath) THEN
		CALL this.exitProgram(SFMT("setup failed: %1 ", stdLib.m_lastError), 1)
	END IF

-- Setup docs storage on the server.
	LET this.cfg.docPath = os.path.join(this.cfg.fileStorage, this.cfg.docPath)
	IF NOT stdLib.mkDir(this.cfg.docPath) THEN
		CALL this.exitProgram(SFMT("setup failed: %1 ", stdLib.m_lastError), 1)
	END IF

	IF this.feName = "GMA" OR this.feName = "GMI" THEN
		LET this.feMobile = TRUE
	END IF

	LET this.connected = FALSE
	LET stdLib.m_timeouts.* = this.cfg.timeouts.*

	DEBUG(1, SFMT("Login Timeout: %1 Confirm: %2", this.cfg.timeouts.login, this.cfg.timeouts.confirm))

	RETURN this
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Get application configuration.
FUNCTION (this mobLib) getConfig() RETURNS()
	DEFINE l_file STRING
	DEFINE l_json TEXT
	DEFINE l_read BOOLEAN
	DEFINE l_jo   util.JSONObject

	LET l_file = os.path.join(this.cfg.cfgPath, this.appName.trim() || ".cfg")
	LET l_read = os.path.exists(l_file)
	LOCATE l_json IN FILE l_file
	IF l_read THEN            -- read the config and override the defaults
		IF this.cfg.useCFG THEN -- only bother reading if we are going to use it.
			--CALL util.JSON.parse(l_json, this.cfg)
			LET l_jo = parse_keep_existing(util.JSONObject.fromFGL(this.cfg), l_json)
			CALL l_jo.toFGL(this.cfg)
		END IF
		IF this.cfg.cfgVersion != C_CFGVER THEN -- save new version of cfg
			LET this.cfg.cfgVersion = C_CFGVER
			LET l_json              = util.JSON.stringify(this.cfg)
--		ELSE -- use the cfg from the json file
--			LET this.cfg = l_cfg
		END IF
-- can't use debug here because log path is not setup correctly yet!!
		DISPLAY SFMT("%1:0:%2:%3:CFG Read: %4", CURRENT, __LINE__ USING "####&", "mobLib.4gl", l_file)
	ELSE
		-- save the config with the default values
		LET l_json = util.JSON.stringify(this.cfg)
		DISPLAY SFMT("%1:0:%2:%3:CFG Written: %4", CURRENT, __LINE__ USING "####&", "mobLib.4gl", l_file)
	END IF

END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Show an about screen with useful information.
FUNCTION (this mobLib) about()
	DEFINE l_txt, l_url, l_cli, l_gbc, l_srv, l_dir STRING

	LET l_dir = os.path.baseName(os.path.pwd())
	IF this.cfg.debug THEN
		RUN "env | sort > /tmp/mobDemo.env"
	END IF

	LET l_url = fgl_getEnv("FGL_VMPROXY_START_URL")
	LET l_cli = this.feName, " ", this.feVer
	LET l_gbc = ui.Interface.getUniversalClientName(), " Ver:", ui.Interface.getUniversalClientVersion()
	IF l_gbc.getLength() > 1 THEN
		LET l_cli = l_cli.append("\nUR: " || l_gbc)
	END IF
	LET l_srv = fgl_getVersion()
	OPEN WINDOW about WITH FORM "mdAbout"
	LET l_txt = SFMT("App: %1 %2\nDir: %3", this.appName, g_appVersion, l_dir)
	IF l_url IS NOT NULL THEN
		LET l_txt = l_txt.append(SFMT("\nURL:\n   %1", l_url))
	END IF
	LET l_txt = l_txt.append(SFMT("\nServer: %1", l_srv))
	LET l_txt =
			l_txt.append(SFMT("\nClient: %1\n\nMobile: %2 ROS: %3", l_cli, IIF(this.feMobile, "True", "False"), this.ros_ver))
	IF this.feMobile THEN
		CALL this.get_mobInfo()
		LET l_txt = l_txt.append(SFMT("\nMob Connected: %1", this.mobdev_info.connected))
		LET l_txt =
				l_txt.append(
						SFMT("\nMob Info: %1 %2 %3\nDataDir: %4",
								this.mobdev_info.model, this.mobdev_info.os, this.mobdev_info.osver, this.mobdev_info.datadir))
		IF this.cli_ip IS NULL THEN
			LET this.cli_ip = this.mobdev_info.ip
		END IF
	END IF
	LET l_txt = l_txt.append(SFMT("\nClient IP: %1", this.cli_ip))
	LET l_txt = l_txt.append(SFMT("\nDev IP: %1", this.reg.dev_ip))
	LET l_txt = l_txt.append(SFMT("\nSession: %1", fgl_getEnv("FGL_VMPROXY_SESSION_ID")))
	LET l_txt = l_txt.append(SFMT("\nDevID: %1", this.reg.dev_id))
	LET l_txt = l_txt.append(SFMT("\nDevID2: %1", this.reg.dev_id2))
	LET l_txt = l_txt.append(SFMT("\n\nDBName: %1", this.dbName))
	LET l_txt = l_txt.append(SFMT("\n\nCoNo: %1", this.reg.cono))
	LET l_txt = l_txt.append(SFMT("\nUser Id: %1", this.user_id))
	LET l_txt = l_txt.append(SFMT("\nEmployee: %1", this.emp_code))
	LET l_txt = l_txt.append(SFMT("\nBranch: %1", this.branch))
	LET l_txt = l_txt.append(SFMT("\nSYSNAME: %1", this.sysName))
	LET l_txt = l_txt.append(SFMT("\nCloudStore: %1", IIF(this.cloudStore, "Enabled", "Disabled")))
	LET l_txt = l_txt.append(SFMT("\nViewFiles: %1", IIF(this.viewFiles, "Enabled", "Disabled")))
	LET l_txt = l_txt.append(SFMT("\nEclipse GenVer: %1", this.eclipseGenVer))
	LET l_txt = l_txt.append(SFMT("\nUse Config: %1", IIF(this.cfg.useCfg, "True", "False")))
	LET l_txt = l_txt.append(SFMT("\nConfig Version: %1", this.cfg.cfgVersion))
	LET l_txt = l_txt.append(SFMT("\nRefreshAge: %1 HH:MM", this.cfg.refreshAge))
	LET l_txt = l_txt.append(SFMT("\nJob Age: %1 Days", this.cfg.jobAge))
	LET l_txt = l_txt.append(SFMT("\nTimeout 'confirm': %1", this.cfg.timeouts.confirm))
	LET l_txt = l_txt.append(SFMT("\nTimeout 'login':   %1", this.cfg.timeouts.login))
	LET l_txt = l_txt.append(SFMT("\nTimeout 'menu':    %1", this.cfg.timeouts.menu))
	LET l_txt = l_txt.append(SFMT("\nTimeout 'long':    %1", this.cfg.timeouts.long))
	LET l_txt = l_txt.append(SFMT("\nTimeout 'medium':  %1", this.cfg.timeouts.medium))
	LET l_txt = l_txt.append(SFMT("\nTimeout 'short':   %1", this.cfg.timeouts.short))
	LET l_txt = l_txt.append(SFMT("\nCfgPath:\n%1\n", this.cfg.cfgPath))
	LET l_txt = l_txt.append(SFMT("\nLogPath:\n%1\n", this.cfg.logPath))
	LET l_txt = l_txt.append(SFMT("\n\ImgPath:\n%1\n", this.cfg.imgPath))
	LET l_txt = l_txt.append(SFMT("\n\DocPath:\n%1\n", this.cfg.docPath))
	LET l_txt = l_txt.append(SFMT("\n\BASEDIR:\n%1\n", this.cfg.baseDir))

	LET l_txt = l_txt.append(SFMT("\n\nAllowTest: %1", IIF(this.cfg.allowTest, "True", "False")))
	LET l_txt = l_txt.append(SFMT("\nIconMenu: %1", IIF(this.cfg.iconMenu, "True", "False")))
	LET l_txt = l_txt.append(SFMT("\nStyle: %1", this.cfg.style))
	LET l_txt = l_txt.append(SFMT("\nDebug: %1", this.cfg.debug))
	LET l_txt = l_txt.append(SFMT("\nGMASettings: %1", IIF(this.cfg.gma_settings, "True", "False")))

	DISPLAY l_txt TO txt
	DEBUG(1, SFMT("about: Menu, timeout is %1", this.cfg.timeouts.short))
	DEBUG(0, util.json.stringify(this))
	MENU
		BEFORE MENU
			IF this.feName != "GMA" THEN
				CALL ui.Window.getCurrent().getForm().setElementHidden("about", TRUE)
			ELSE
				IF this.cfg.gma_settings THEN
					CALL ui.Window.getCurrent().getForm().setElementHidden("settings", FALSE)
				END IF
			END IF
			IF this.emp_code IS NOT NULL THEN
				CALL DIALOG.setActionActive("clear", FALSE)
			END IF
		ON ACTION close
			EXIT MENU
		ON ACTION about
			CALL ui.Interface.frontCall("android", "showAbout", [], [])
		ON ACTION settings
			CALL ui.Interface.frontCall("android", "showSettings", [], [])
		ON ACTION clear
			IF fgl_winQuestion("Confirm", "Are you sure you want to degregister this device?", "No", "Yes|No", "question", 1)
					= "Yes" THEN
				CALL ui.Interface.frontCall("localStorage", "removeItem", [this.appName], [])
				CALL this.exitProgram("Clear registration", 0)
			END IF
		ON ACTION back
			EXIT MENU
		ON IDLE this.cfg.timeouts.short
			EXIT MENU
		ON ACTION enterbackground
			EXIT MENU
	END MENU
	CLOSE WINDOW about
END FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION (this mobLib) futureFeature(l_feature STRING) RETURNS()
	CALL stdLib.popup(l_feature, "This feature is planned for a future release.", "info", 0)
END FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION (this mobLib) get_mobInfo()
	CALL ui.Interface.frontCall("mobile", "connectivity", [], [this.mobdev_info.connected])
	IF this.mobdev_info.model IS NOT NULL THEN
		RETURN
	END IF
	TRY
		CALL ui.Interface.frontCall("standard", "feinfo", "ip", [this.mobdev_info.ip])
	CATCH
	END TRY
	DEBUG(1, SFMT("deviceRegister: FEInfo ip: %1", this.mobdev_info.ip))
	TRY
		CALL ui.Interface.frontCall("standard", "feinfo", "deviceModel", [this.mobdev_info.model])
	CATCH
	END TRY
	DEBUG(1, SFMT("deviceRegister: FEInfo deviceModel: %1", this.mobdev_info.model))
	TRY
		CALL ui.Interface.frontCall("standard", "feinfo", "osType", [this.mobdev_info.os])
	CATCH
	END TRY
	DEBUG(1, SFMT("deviceRegister: FEInfo osType: %1", this.mobdev_info.os))
	TRY
		CALL ui.Interface.frontCall("standard", "feinfo", "osVersion", [this.mobdev_info.osver])
	CATCH
	END TRY
	DEBUG(1, SFMT("deviceRegister: FEInfo osVersion: %1", this.mobdev_info.osver))
	TRY
		CALL ui.Interface.frontCall("standard", "feinfo", "dataDirectory", [this.mobdev_info.datadir])
	CATCH
	END TRY
	DEBUG(1, SFMT("deviceRegister: FEInfo dataDirectory: %1", this.mobdev_info.datadir))

END FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION (this mobLib) timeout(l_func STRING)
	DEFINE l_abort BOOLEAN = TRUE
	DEFINE l_fg    BOOLEAN = FALSE

	DEBUG(2, SFMT("Timeout in function: %1 ", l_func))
	IF this.feMobile THEN
		CALL ui.Interface.frontCall("mobile", "isForeground", [], [l_fg])
		IF NOT l_fg THEN
			CALL this.exitProgram(SFMT("timeout in %1 in background", l_func), 0)
		END IF
	END IF

	IF this.cfg.timeouts.confirm > 0 THEN
		MENU "Idle" ATTRIBUTES(STYLE = "dialog", COMMENT = "The application is about to timeout", IMAGE = "information")
			COMMAND "Continue"
				LET l_abort = FALSE
			COMMAND "Close"
				DISPLAY "Closed"
			ON IDLE this.cfg.timeouts.confirm
				DEBUG(2, "Timed out")
		END MENU
	END IF
	IF l_abort THEN
		CALL this.exitProgram(SFMT("timeout in %1", l_func), 0)
	END IF
END FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION (this mobLib) doMenu(l_titl STRING, l_doMenu BOOLEAN) RETURNS SMALLINT
	DEFINE l_but  om.DomNode
	DEFINE l_buts om.NodeList
	DEFINE x      SMALLINT = 0

	DISPLAY l_titl TO menu_title
	LET l_buts = ui.Window.getCurrent().getNode().selectByTagName("Button")
	FOR x = 1 TO l_buts.getLength()
		LET l_but = l_buts.item(x)
		IF this.buttons[x].text IS NOT NULL THEN
			CALL l_but.setAttribute("hidden", FALSE)
			CALL l_but.setAttribute("text", this.buttons[x].text)
			IF this.buttons[x].img IS NOT NULL THEN
				CALL l_but.setAttribute("image", this.buttons[x].img)
			END IF
			IF this.buttons[x].text = "Back" THEN
				CALL l_but.setAttribute("style", "menubutton2")
			ELSE
				CALL l_but.setAttribute("style", "menubutton")
			END IF
		END IF
	END FOR

	IF NOT l_doMenu THEN
		RETURN 0
	END IF
	DEBUG(1, SFMT("doMenu: Menu '%1', timeout is %2", l_titl, this.cfg.timeouts.menu))
	MENU
		BEFORE MENU
			CALL this.menuSetActive(DIALOG)
		COMMAND "opt1"
			LET x = 1
			EXIT MENU
		COMMAND "opt2"
			LET x = 2
			EXIT MENU
		COMMAND "opt3"
			LET x = 3
			EXIT MENU
		COMMAND "opt4"
			LET x = 4
			EXIT MENU
		COMMAND "opt5"
			LET x = 5
			EXIT MENU
		COMMAND "opt6"
			LET x = 6
			EXIT MENU
		COMMAND "opt7"
			LET x = 7
			EXIT MENU
		COMMAND "opt8"
			LET x = 8
			EXIT MENU

		ON ACTION close
			LET x = 0
			EXIT MENU

		ON IDLE this.cfg.timeouts.menu
			CALL this.timeout("doMenu")
			LET x = 0
			EXIT MENU

		ON ACTION enterbackground
			LET x = 0
			EXIT MENU
	END MENU

	RETURN x
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- set the active state for the menu items
FUNCTION (this mobLib) menuSetActive(d ui.Dialog)
	DEFINE x SMALLINT
	FOR x = 1 TO this.buttons.getLength()
		IF NOT this.buttons[x].enabled THEN
			CALL d.setActionActive("opt" || x, FALSE)
		END IF
	END FOR
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Show a file
FUNCTION (this mobLib) showFile(l_path STRING, l_file STRING, l_show BOOLEAN) RETURNS STRING
	DEFINE l_line, l_uri, l_fileName STRING
	DEFINE l_ret                     SMALLINT

	LET l_line = os.path.JOIN(l_path, l_file)
	IF os.path.exists(l_line) THEN
		LET l_fileName = os.path.basename(l_line)
		IF NOT l_show THEN
			RETURN l_fileName
		END IF
		LET l_file = os.Path.join("/sdcard/Download", l_fileName)
		DEBUG(3, SFMT("showFile: %1 %2", l_line, l_file))
		TRY
			CALL fgl_putFile(l_line, l_file)
		CATCH
			CALL stdLib.error(SFMT("putFile %1 %2\nFailed: %3 %4", l_line, l_file, STATUS, ERR_GET(STATUS)), TRUE)
			-- failed to copy so change it back to the remote file path.
			LET l_file = l_line
		END TRY
		IF this.feName != "GBC" THEN
			LET l_uri = ui.Interface.filenameToURI(l_file)
			CALL ui.Interface.frontCall("standard", "launchURL", l_file, l_ret)
			DEBUG(3, SFMT("showFile:launchURL %1 (%2)", l_uri, l_ret))
		END IF
	ELSE
		CALL error(SFMT("Didn't find file %1", l_file), TRUE)
	END IF
	RETURN l_fileName
END FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION (this mobLib) openForm(l_form STRING) RETURNS STRING
	IF this.cfg.style > 0 THEN
		IF os.path.exists(l_form || this.cfg.style || ".42f") THEN
			LET l_form = l_form || this.cfg.style
		END IF
	END IF
	DEBUG(3, SFMT("Form: %1", l_form))
	RETURN l_form
END FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION (this mobLib) exitProgram(l_reason STRING, l_stat SMALLINT) RETURNS()
	DEFINE l_msg STRING
	LET l_msg = SFMT("exit: %1 %2 emp: %3", l_stat, l_reason, this.emp_code)
	IF l_stat = 0 THEN
		DEBUG(1, l_msg)
	ELSE
		DEBUG(0, l_msg)
	END IF
	IF this.emp_code IS NOT NULL AND this.branch IS NOT NULL THEN
		LET l_msg = logDeviceLogin(this.emp_code, this.branch, "T", FALSE)
	END IF
	EXIT PROGRAM l_stat
END FUNCTION
