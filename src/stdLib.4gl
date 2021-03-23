-- Generic Library functions
IMPORT os
IMPORT util
IMPORT security
&define DEBUG( l_lev, l_msg ) IF m_debug THEN CALL debugOut( l_lev, __FILE__,__LINE__, l_msg ) END IF

PUBLIC DEFINE m_timeouts RECORD -- set from mobLib
	login   SMALLINT,
	confirm SMALLINT,
	menu    SMALLINT,
	short   SMALLINT,
	medium  SMALLINT,
	long    SMALLINT
END RECORD

PUBLIC DEFINE m_debug     SMALLINT
PUBLIC DEFINE m_lastError STRING
PUBLIC DEFINE m_logPath   STRING
PUBLIC DEFINE m_debugFile STRING
PUBLIC DEFINE m_notify    BOOLEAN
FUNCTION stdlib_dummy()
	WHENEVER ERROR CALL app_error
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Popup a message box with a timeout value.
FUNCTION popup(l_titl STRING, l_msg STRING, l_img STRING, l_timeout SMALLINT)
	IF l_timeout = 0 THEN
		LET l_timeout = m_timeouts.confirm
	END IF
	DEBUG(2, SFMT("popup: Msg: %1 Timeout: %2", l_msg, l_timeout))
	MENU l_titl ATTRIBUTES(STYLE = "dialog", COMMENT = l_msg, IMAGE = l_img)
		ON ACTION continue
		ON IDLE l_timeout
	END MENU
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Popup an Error box with a timeout value.
FUNCTION error(l_msg STRING, l_popup BOOLEAN)
	LET m_lastError = l_msg
	DEBUG(0, SFMT("Error: %1", l_msg))
	IF l_popup THEN
		CALL popup("Error", l_msg, "exclamation", m_timeouts.medium)
	ELSE
		ERROR l_msg
	END IF
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Popup a Warning box with a timeout value.
FUNCTION warning(l_msg STRING, l_popup BOOLEAN)
	LET m_lastError = l_msg
	DEBUG(0, SFMT("Warning: %1", l_msg))
	IF l_popup THEN
		CALL popup("Warning", l_msg, "information", m_timeouts.medium)
	ELSE
		ERROR l_msg
	END IF
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Confirm Yes/No with a timeout.
FUNCTION confirm(l_msg STRING, l_def BOOLEAN, l_idle SMALLINT) RETURNS BOOLEAN
	DEFINE l_ans BOOLEAN
	IF l_idle = 0 THEN
		LET l_idle = m_timeouts.confirm
	END IF
	MENU "Confirm" ATTRIBUTES(STYLE = "dialog", COMMENT = l_msg, IMAGE = "question")
		BEFORE MENU
			IF l_def = TRUE THEN
				NEXT OPTION "yes"
			END IF
		ON ACTION no
			LET l_ans = FALSE
		ON ACTION yes
			LET l_ans = TRUE
		ON IDLE l_idle
			LET l_ans = l_def
	END MENU
	RETURN l_ans
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Debug output.
FUNCTION debugOut(l_lev SMALLINT, l_mod STRING, l_lineno SMALLINT, l_msg STRING) RETURNS()
	DEFINE c      base.Channel
	DEFINE l_line STRING
	DEFINE l_dte  STRING

	IF m_debug IS NULL THEN
		LET m_debug = 0
	END IF
	IF m_debugFile IS NULL THEN
		IF m_logPath.trim().getLength() < 1 THEN
			LET m_logPath = fgl_getEnv("TRIMLOGDIR")
			IF m_logPath.trim().getLength() < 1 THEN
				LET m_logPath = "."
			END IF
		END IF
		LET l_dte = util.Datetime.format(CURRENT, "%Y%m%d_%H%M%S")
		LET m_debugFile =
				os.path.join(m_logPath, base.Application.getProgramName() || "_" || l_dte || "." || fgl_getPid() || ".log")
		DISPLAY CURRENT, ":DebugLog:", m_debugFile
	END IF
	IF l_lev > m_debug THEN
		RETURN
	END IF
	LET l_mod  = os.path.baseName(l_mod)
	LET l_line = CURRENT, ":", l_lev USING "&", ":", l_lineno USING "####&", ":", l_mod, ":", NVL(l_msg, "NULL")
	DISPLAY l_line
	LET c = base.Channel.create()
	CALL c.openFile(m_debugFile, "a+")
	CALL c.writeLine(l_line)
	CALL C.close()
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Make a directory if it doesn't exist.
FUNCTION mkDir(l_dir STRING) RETURNS BOOLEAN
	IF NOT os.path.exists(l_dir) THEN
		IF NOT os.path.mkdir(l_dir) THEN
			CALL error(SFMT("Failed to create folder '%1'\n%2 : %3", l_dir, STATUS, ERR_GET(STATUS)), TRUE)
			RETURN FALSE
		END IF
	ELSE
		IF NOT os.path.isDirectory(l_dir) THEN
			CALL error(SFMT("'%1' is not a directory!\n%2 : %3", l_dir, STATUS, ERR_GET(STATUS)), TRUE)
			RETURN FALSE
		END IF
	END IF
	RETURN TRUE
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Merge JSON object with a new JSON string
FUNCTION parse_keep_existing(o util.JSONObject, s STRING) RETURNS util.JSONObject
	CALL merge_json_objects(o, util.JSONObject.parse(s))
	RETURN o
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Merge two json object structures.
FUNCTION merge_json_objects(o1 util.JSONObject, o2 util.JSONObject) RETURNS()
	DEFINE i      INT
	DEFINE l_name STRING
	FOR i = 1 TO o2.getLength()
		LET l_name = o2.name(i)
		CASE o2.getType(l_name)
			WHEN "OBJECT"
				IF o1.has(l_name) THEN
					CALL merge_json_objects(o1.get(l_name), o2.get(l_name))
				END IF
				# WHEN "ARRAY" -- feel free to implement merge array
			OTHERWISE
				CALL o1.put(l_name, o2.get(l_name))
		END CASE
	END FOR
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Notify Window
FUNCTION notify(l_msg STRING) RETURNS()
	IF m_notify AND l_msg IS NULL THEN
		CLOSE WINDOW notify
		CALL ui.Interface.refresh()
		LET m_notify = FALSE
		RETURN
	END IF
	IF NOT m_notify THEN
		OPEN WINDOW notify WITH FORM "notify"
		LET m_notify = TRUE
	END IF
	DEBUG(2, SFMT("notify: %1", l_msg))
	DISPLAY l_msg TO msg
	CALL ui.Interface.refresh()
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Show the password
FUNCTION toggleShowPass(l_node om.domNode, l_show BOOLEAN)
	CALL l_node.setAttribute("isPassword", l_show)
	CALL l_node.setAttribute("image", IIF(l_show, "visibility", "visibility_off"))
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Generate a unique ID
FUNCTION generateId() RETURNS STRING
	DEFINE l_id STRING
	LET l_id = security.RandomGenerator.CreateUUIDString()
	RETURN l_id
END FUNCTION
