{
Demo mobile application.
Expected to be run via Genero Mobile using the 'runOnServer' application
Arg1: <database>
Arg2: <api name>
Arg3: <version of ros server program>
}

IMPORT FGL wc_iconMenu
IMPORT FGL mdUsers
IMPORT FGL mdTasks
IMPORT FGL mobLib
IMPORT FGL stdLib
IMPORT FGL dbLib
IMPORT FGL mobRegister

&define DEBUG( l_lev, l_msg ) IF m_mobLib.cfg.debug THEN CALL stdLib.debugOut( l_lev, __FILE__, __LINE__, l_msg ) END IF

CONSTANT C_TITL            = "Mobile Demo"
CONSTANT C_APPNAME         = "mobDemo"
CONSTANT C_VER             = "0.7"
CONSTANT C_ICON_CLOCKEDON  = "clockedon"
CONSTANT C_ICON_CLOCKEDOFF = "clockedoff"
CONSTANT C_JOBS_FEATURE    = FALSE
CONSTANT C_SEARCH_FEATURE  = FALSE

GLOBALS
	DEFINE g_appVersion STRING
END GLOBALS

DEFINE m_menu   wc_iconMenu
DEFINE m_mobLib mobLib
DEFINE m_user   mdUsers
DEFINE m_tasks  mdTasks

MAIN
	DEFINE l_titl     STRING
	DEFINE l_menuForm STRING
	DEFINE l_info     STRING

	OPTIONS ON TERMINATE SIGNAL CALL app_terminate, ON CLOSE APPLICATION CALL app_close
	WHENEVER ERROR CALL app_error

	LET g_AppVersion = C_VER
	LET m_mobLib     = m_mobLib.init(C_APPNAME)
	LET l_titl       = C_TITL || " " || C_VER
	CALL stdLib.debugOut(0, __FILE__, __LINE__, SFMT("%1 PID: %2", l_titl, fgl_getPID()))
	CALL dbLib.init(m_mobLib)
	IF NOT mobRegister.deviceRegister(m_mobLib) THEN -- check device is registered and connect to DB.
		CALL m_mobLib.exitProgram("main - not registered", 1)
	END IF
	DEBUG(1, SFMT("main: dev_id: %1 main", m_mobLib.reg.dev_id))

	IF m_mobLib.cfg.iconMenu THEN
		LET l_menuForm = "wc_iconMenu"
	ELSE
		LET l_menuForm = "mdMainMenu"
	END IF
	OPEN FORM menu FROM l_menuForm

	IF fgl_getEnv("SHOWINFO") = 1 THEN
		LET l_info = dbLib.getMOD()
		{SFMT("<p style=\"font-size:14px;\">&nbsp;Don't forget to %1 due to %2&nbsp;</p>",
				'<i class="material-icons">clean_hands</i>', '<i class="material-icons">coronavirus</i>')}
	END IF
	WHILE TRUE
		LET m_mobLib.emp_code = NULL
		LET m_mobLib.branch   = NULL
		LET m_user            = m_user.init(m_mobLib)
		IF NOT m_user.login(l_titl, l_info) THEN
			CALL m_mobLib.exitProgram("Login Failed", 1)
		END IF
		LET m_mobLib.user_id  = m_user.emp_rec.user_id
		LET m_mobLib.emp_code = m_user.emp_rec.short_code
		LET m_mobLib.branch   = m_user.branch
		CALL dbLib.init(m_mobLib)

		LET m_mobLib.cloudStore = FALSE

		DISPLAY FORM menu
		IF NOT m_menu.init("mdMenu.json", m_mobLib.cfg.iconMenu) THEN
			CALL m_mobLib.exitProgram("Menu init failed", 1)
		END IF
		LET m_menu.debug = m_mobLib.cfg.debug
		CALL m_tasks.init(m_user, m_mobLib)
		CALL mainMenu()
	END WHILE

END MAIN
--------------------------------------------------------------------------------------------------------------
FUNCTION mainMenu() RETURNS()
	DEFINE l_menuItem    STRING
	DEFINE l_msg         STRING
	DEFINE l_ret         BOOLEAN
	DEFINE l_logout_meth CHAR(1)
	LET l_menuItem = "x"
	LET l_ret      = m_menu.itemActive("search", FALSE)
	DISPLAY m_user.top_image TO img
	DISPLAY m_user.emp_rec.full_name TO usern
	WHILE l_menuItem != "logoff" AND l_menuItem != "close" AND l_menuItem != "timeout"
		LET l_ret = m_menu.itemActive("curtasks", FALSE)
		LET l_ret = m_menu.itemActive("mytasks", FALSE)
		--LET l_ret = m_menu.itemActive("wip", FALSE)
		LET l_ret = m_menu.itemActive("jobs", FALSE)
		LET l_ret = m_menu.itemActive("search", FALSE)
		LET l_ret = m_menu.itemActive("misctask", FALSE)
		IF m_user.state THEN
			IF m_user.emp_rec.productive != "N" THEN -- unproductive emps can only clock on and clock off.
				LET l_ret = m_menu.itemActive("curtasks", TRUE)
				LET l_ret = m_menu.itemActive("mytasks", TRUE)
				LET l_ret = m_menu.itemActive("misctask", TRUE)
				--LET l_ret = m_menu.itemActive("wip", C_WIP_FEATURE)
				LET l_ret = m_menu.itemActive("jobs", C_JOBS_FEATURE)
				LET l_ret = m_menu.itemActive("search", C_SEARCH_FEATURE)
			END IF
--			LET l_ret = m_menu.itemText("clockevent", "Clock Off")
			LET l_ret = m_menu.itemState("clockevent", 2)
		ELSE
--			LET l_ret = m_menu.itemText("clockevent", "Clock On")
			LET l_ret = m_menu.itemState("clockevent", 1)
		END IF
		IF m_user.onMiscTask THEN
			LET l_ret = m_menu.itemState("misctask", 2)
		ELSE
			LET l_ret = m_menu.itemState("misctask", 1)
		END IF
		DISPLAY IIF(m_user.state, C_ICON_CLOCKEDON, C_ICON_CLOCKEDOFF) TO imgstat
		DISPLAY IIF(m_user.state, "Clocked On", "Not Clocked On") TO status
		LET l_menuItem = m_menu.ui(0, m_mobLib.cfg.timeouts.menu) -- WC menu
		DEBUG(1, SFMT("mainMenu: %1", l_menuItem))
		CASE l_menuItem
			WHEN "clockevent"
				CALL m_user.clockEvent()
				IF NOT m_user.state THEN
					EXIT WHILE
				END IF
			WHEN "curtasks"
				CALL m_tasks.showList(1, TRUE) --	View Started Tasks Allocationed to Me
			WHEN "mytasks"
				CALL m_tasks.showList(2, TRUE) --	View All Tasks Allocationed to Me
			WHEN "wip"
				CALL m_tasks.showList(3, TRUE) --	View WIP
			WHEN "misctask"
				LET m_user.onMiscTask = NOT m_user.onMiscTask
			WHEN "search"
				CALL m_tasks.search() -- Search for jobs
			WHEN "empenq"
				CALL m_user.emp_enq()     -- Employ Enquiry
				CALL m_tasks.list.clear() -- clear the tasks list to force a refresh of data so emp_enq number agree
			WHEN "about"
				DISPLAY "MU:", m_user.mobLib.user_id, " M:", m_mobLib.user_id, " MT:", m_tasks.mobLib.user_id
				CALL m_mobLib.about()
			WHEN "logoff"
				LET l_logout_meth = "L"
			WHEN "close"
				LET l_logout_meth = "C"
			WHEN "timeout"
				LET l_logout_meth = "T"
		END CASE
	END WHILE
	LET l_msg = dbLib.logDeviceLogin(m_user.emp_rec.short_code, m_user.branch, l_logout_meth, FALSE)
END FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION app_error()
	DEFINE l_st   STRING
	DEFINE l_stat SMALLINT
	LET l_stat = STATUS
	LET l_st   = base.Application.getStackTrace()
	DEBUG(0, SFMT("CRASH: %1 %2\n%3", l_stat, ERR_GET(l_stat), l_st))
	CALL stdLib.error("Something unexpected happened\nPlease contact main office.", TRUE)
	CALL m_mobLib.exitProgram("closed because of crash", 0)
END FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION app_close()
	CALL m_mobLib.exitProgram("closed by client end", 0)
END FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION app_terminate()
	CALL m_mobLib.exitProgram("terminated by server end", 0)
END FUNCTION
