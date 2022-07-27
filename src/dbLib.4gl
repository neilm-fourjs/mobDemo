IMPORT util
IMPORT os
IMPORT security
IMPORT FGL stdLib
IMPORT FGL mobLib

&include "schema.inc"

CONSTANT C_DOCEXT = "doc"
CONSTANT C_PDFEXT = "pdf"
CONSTANT C_IMGEXT = "jpg"

&define DEBUG( l_lev, l_msg ) IF m_db_mobLib.cfg.debug THEN CALL stdLib.debugOut( l_lev, __FILE__, __LINE__, l_msg ) END IF

-- uncomment to disable update/delete from database.
&define NOUPD 1
&define DUMPDATA 1
&define OPTIMIZE1

PUBLIC TYPE t_listData1 RECORD
	branch_code    CHAR(2),
	job_number     LIKE job01.job_number,
	job_link       LIKE job01.job_link,
	work_code      LIKE trim1.work_code,
	list_title     LIKE lists.list_title,
	emp_code       LIKE trim2.employee_code,
	started        LIKE trim2.start_datetime,
	stopped        LIKE trim2.end_datetime,
	list_link      LIKE lista.list_link,
	workshop_hrs   LIKE lista.workshop_hours,
	actual_hrs     LIKE lista.actual_hours,
	time_remaining DECIMAL(6, 2),
	sch_handover   DATE,
	list_status    SMALLINT,
	trim_cmd       CHAR(1),
	trim_stop      CHAR(1),
	in_trim1       BOOLEAN,
	in_trim2       BOOLEAN,
	in_next_job    BOOLEAN,
	state_desc     STRING,
	veh_reg        LIKE vehicle.vehicle_id,
	veh_make       STRING,
	veh_colour     STRING,
	contact        LIKE job01.contact_name,
	priority       LIKE next_job.priority,
	trim           SMALLINT
END RECORD

PUBLIC TYPE t_branches DYNAMIC ARRAY OF RECORD
	branch_code CHAR(2),
	branch_name VARCHAR(40)
END RECORD
PUBLIC DEFINE m_db_mobLib  mobLib
PUBLIC DEFINE m_doPopups   BOOLEAN = TRUE
PUBLIC DEFINE m_connected  BOOLEAN
PUBLIC DEFINE m_dbName     STRING
PUBLIC DEFINE m_debug      SMALLINT
PUBLIC DEFINE m_jobsFound  INTEGER
PUBLIC DEFINE m_tasksFound INTEGER
PUBLIC DEFINE m_lastError  STRING
PUBLIC DEFINE m_cloudStore BOOLEAN

--------------------------------------------------------------------------------------------------------------
FUNCTION init(l_mobLib mobLib INOUT)
	LET m_db_mobLib = l_mobLib
	IF m_db_mobLib.branch IS NULL OR m_db_mobLib.branch = " " THEN
		RETURN
	END IF
END FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION connectDB(l_db STRING) RETURNS BOOLEAN
	WHENEVER ERROR CALL app_error
	IF NOT m_connected THEN
		DEBUG(2, SFMT("connectDB: Connecting to '%1'", l_db))
		LET m_dbName = l_db
		TRY
			CONNECT TO l_db
		CATCH
			CALL dbLib_error(SFMT("Failed to connect to database '%1'\n%2", l_db, SQLERRMESSAGE))
			RETURN FALSE
		END TRY
		DEBUG(2, SFMT("connectDB: Connected to '%1'", l_db))
	END IF
	LET m_connected = TRUE
	RETURN TRUE
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Check that a specific table exists.
FUNCTION checkTable(l_tab STRING) RETURNS BOOLEAN
	DEFINE l_str STRING
	DEFINE l_cre BOOLEAN = FALSE
	DEFINE l_cnt SMALLINT
	DEBUG(2, SFMT("checkTable: %1 ...", l_tab))
	LET l_str = SFMT("SELECT COUNT(*) FROM %1", l_tab)
	TRY
		PREPARE l_pre FROM l_str
		DECLARE chkTab CURSOR FOR l_pre
		OPEN chkTab
		FETCH chkTab INTO l_cnt
	CATCH
		LET l_cre = TRUE
	END TRY
	IF l_cre THEN
		CASE l_tab
			WHEN "mobdemoreg"
				LET l_str =
						"CREATE TABLE mobdemoreg( app_name VARCHAR(20), dev_id VARCHAR(50), ip VARCHAR(80), cono CHAR(4),user_id CHAR(10), when_ts DATETIME YEAR TO SECOND)"
			OTHERWISE
				RETURN FALSE
		END CASE
		TRY
			EXECUTE IMMEDIATE l_str
			DEBUG(2, SFMT("checkTable: %1 created.", l_tab))
		CATCH
			CALL dbLib_error(SFMT("Failed to create table! '%1'", l_tab))
			RETURN FALSE
		END TRY
	END IF
	DEBUG(2, SFMT("checkTable: %1 Okay.", l_tab))
	RETURN TRUE
END FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION validUser(l_user STRING, l_pwd STRING) RETURNS(BOOLEAN, STRING)
	DEFINE l_users RECORD LIKE users.*
	DEBUG(2, SFMT("validUser: %1 ...", l_user))
	SELECT * INTO l_users.* FROM users WHERE users.user_id = l_user
	IF STATUS = NOTFOUND THEN
		DEBUG(2, SFMT("validUser: not in db", l_user))
		RETURN FALSE, NULL
	END IF
-- Hack for testing only - only works if user 'test' actually exists in the data - which it shouldn't
	IF l_user.subString(1, 4) = "test" AND l_pwd = "test" AND m_db_mobLib.cfg.allowTest THEN
		RETURN TRUE, l_users.user_name
	END IF
-- Actually check the users password.
	IF NOT checkPassword(l_pwd.trim(), l_users.user_password CLIPPED, FALSE) THEN
		RETURN FALSE, l_users.user_name
	END IF

	DEBUG(2, SFMT("validUser: %1 Okay.", l_user))
	RETURN TRUE, l_users.user_name
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Check the password is valid
FUNCTION checkPassword(l_pass STRING, l_hash STRING, l_emp BOOLEAN) RETURNS BOOLEAN
-- TODO remove when testing finished.
	DEBUG(3, SFMT("checkPassword: allowTest %1", m_db_mobLib.cfg.allowTest))
	IF l_pass = "test" AND m_db_mobLib.cfg.allowTest AND l_emp THEN
		RETURN TRUE
	END IF -- TODO: remove before go live!!
--	DEBUG(3, SFMT("PWD: %1 vs %2", l_pass.trim(), l_hash.trim()))
	TRY
		IF NOT security.BCrypt.CheckPassword(l_pass.trim(), l_hash.trim()) THEN
			RETURN FALSE
		END IF
	CATCH
		DEBUG(3, "password hash probably invalid!")
		RETURN FALSE
	END TRY
	RETURN TRUE
END FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION getEmployee(l_empCode LIKE emp01.short_code, l_branch LIKE emp01.branch_code, l_pwd STRING)
		RETURNS(RECORD LIKE emp01.*)
	DEFINE l_emp  RECORD LIKE emp01.*
	DEFINE l_hash STRING

	DEBUG(2, SFMT("getEmployee: %1 @ %2 ...", l_empCode, l_branch))
	SELECT * INTO l_emp.* FROM emp01
			WHERE short_code = l_empCode AND branch_code = l_branch AND (leave_date IS NULL OR leave_date > DATE(TODAY))
	--	AND (emp01.productive = "Y" OR emp01.productive = "O") -- non productive can still clock on/off ?
	IF STATUS = NOTFOUND THEN
		CALL dbLib_error(SFMT("Employee %1 for branch %2 not found!", l_empCode, l_branch))
		INITIALIZE l_emp TO NULL
		RETURN l_emp
	END IF
	DEBUG(2, SFMT("getEmployee: %1 @ %2 Okay", l_empCode, l_branch))

	IF l_pwd IS NULL THEN
		RETURN l_emp
	END IF

	SELECT * FROM device_login WHERE emp_user = l_empCode AND branch_code = l_branch AND app_name = m_db_mobLib.appName
	IF STATUS = NOTFOUND THEN
		INSERT INTO device_login
				VALUES(l_empCode, l_branch, m_db_mobLib.appName, m_db_mobLib.reg.dev_id, m_db_mobLib.reg.dev_id2,
						m_db_mobLib.reg.dev_ip, m_db_mobLib.cli_ip, NULL, NULL, NULL, NULL, 0, "N")
	END IF

-- If they have a user_id then validate their password - if it's supplied - NOTE: it's not passed when just checking the employee
-- for starting a task.

	IF l_emp.user_id IS NOT NULL THEN
		SELECT user_password INTO l_hash FROM users WHERE user_id = l_emp.user_id
		IF NOT checkPassword(l_pwd.trim(), l_hash.trim(), TRUE) THEN
--TODO: Add in the invalid login checks / count here.
			DEBUG(2, "Invalid Login Details")
			INITIALIZE l_emp TO NULL
			RETURN l_emp
		END IF
	ELSE
		IF l_pwd != "test" THEN
			INITIALIZE l_emp TO NULL
		END IF
		CALL stdLib.error("Your account is not setup for this application.\nContact the main office.", TRUE)
		-- TODO: when testing finished this error will be fatal and return NULL - for now allow it to pass
	END IF

	RETURN l_emp
END FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION checkEmployee(l_empCode LIKE emp01.short_code) RETURNS(BOOLEAN, t_branches)
	DEFINE l_emp      RECORD LIKE emp01.*
	DEFINE l_branches t_branches
	DEFINE x          SMALLINT = 0
	DEBUG(2, SFMT("checkEmployee: Fetch employee records for %1 ...", l_empCode))
	DECLARE emp_cur CURSOR FOR
			SELECT * FROM emp01 WHERE short_code = l_empCode AND (leave_date IS NULL OR leave_date > DATE(TODAY))
	--	AND (emp01.productive = "Y" OR emp01.productive = "O") -- non productive can still clock on/off ?
	FOREACH emp_cur INTO l_emp.*
		IF l_emp.branch_code IS NOT NULL THEN
			LET x                         = x + 1
			LET l_branches[x].branch_code = l_emp.branch_code
			SELECT branch_name INTO l_branches[x].branch_name FROM bra01 WHERE branch_code = l_emp.branch_code
			IF STATUS = NOTFOUND OR l_branches[x].branch_name = "DELETED" THEN
				CALL l_branches.deleteElement(x)
				LET x = x - 1
			END IF
		END IF
	END FOREACH
	IF x = 0 THEN
		RETURN FALSE, NULL
	END IF
	DEBUG(2, SFMT("checkEmployee: Found %1 employee records for %2 ...", x, l_empCode))
	RETURN TRUE, l_branches
END FUNCTION
--------------------------------------------------------------------------------------------------------------
{
device_login (
            emp_user CHAR(10),
            branch_code CHAR(2),
            last_app_name VARCHAR(20),
            last_dev_id VARCHAR(40),
            last_dev_id2 VARCHAR(40),
            last_dev_ip VARCHAR(80),
            last_ip VARCHAR(80),
            last_login DATETIME YEAR TO SECOND,
            last_logout DATETIME YEAR TO SECOND,
            logout_method CHAR(1),
            last_failed_attempt DATETIME YEAR TO SECOND,
            failed_attempts SMALLINT,
            logged_in CHAR(1)
}
FUNCTION logDeviceLogin(
		l_empCode LIKE emp01.short_code, l_branch LIKE bra01.branch_code, l_method CHAR(1), l_login BOOLEAN) RETURNS(STRING)
	DEFINE l_last_dev_id STRING
	DEFINE l_logged_in   CHAR(1)
	DEFINE l_last_login  DATETIME YEAR TO SECOND
	DEBUG(1, SFMT("logDeviceLogin: %1 %2 %3 %4", l_empCode, l_branch, l_method, l_login))
	IF l_login THEN
		SELECT last_dev_id2, logged_in, last_login INTO l_last_dev_id, l_logged_in, l_last_login FROM device_login
				WHERE emp_user = l_empCode AND branch_code = l_branch AND app_name = m_db_mobLib.appName
		IF l_logged_in = "Y" AND l_last_dev_id != m_db_mobLib.reg.dev_id2 THEN
			DEBUG(0, SFMT("%1 Already logged in %2 since %3", l_empCode, l_last_dev_id, l_last_login))
			RETURN SFMT("You are already logged in on another device\nSince %1", l_last_login)
		END IF
		LET l_last_login = CURRENT
		UPDATE device_login SET (last_dev_id, last_dev_id2, last_dev_ip, last_ip, last_login, failed_attempts, logged_in)
				= (m_db_mobLib.reg.dev_id, m_db_mobLib.reg.dev_id2, m_db_mobLib.reg.dev_ip, m_db_mobLib.cli_ip, l_last_login, 0,
						"Y")
				WHERE emp_user = l_empCode AND branch_code = l_branch AND app_name = m_db_mobLib.appName
	ELSE
		LET l_last_login = CURRENT
		UPDATE device_login SET (logged_in, last_logout, logout_method) = ("N", l_last_login, l_method)
				WHERE emp_user = l_empCode AND branch_code = l_branch AND app_name = m_db_mobLib.appName
	END IF
	RETURN NULL
END FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION clockOff(l_empCode LIKE emp01.short_code) RETURNS BOOLEAN
	DEFINE l_clock_time DATETIME YEAR TO SECOND

	DEBUG(2, SFMT("clockOff: Emp %1 ",l_empCode))


	LET l_clock_time = CURRENT

	RETURN TRUE
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Returns TRUE/FALSE for the clock on event and the number of active tasks restarted.
FUNCTION clockOn(l_empCode LIKE emp01.short_code) RETURNS(BOOLEAN, SMALLINT)
	DEFINE l_active SMALLINT
	DEFINE l_clock_time DATETIME YEAR TO SECOND

	DEBUG(2, SFMT("clockOff: Emp %1 ",l_empCode))

	LET l_clock_time = CURRENT

	Let l_active = activeTasks( l_empCode )
	RETURN TRUE, l_active
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Return task active count
FUNCTION activeTasks(l_empCode LIKE emp01.short_code) RETURNS SMALLINT
	DEFINE l_count1 SMALLINT

	DEBUG(3, SFMT("activeTasks: emp: %1 count1: %2", l_empCode, l_count1))
	RETURN l_count1
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Do the SQL's to actually get the claimed time
FUNCTION getClaimedTime(l_empCode LIKE emp01.short_code) RETURNS DECIMAL(10,2)
	DEFINE l_claimed_time DECIMAL(10, 2)

	DEBUG(2, SFMT("getClaimedTime: Emp %1 ",l_empCode))


	RETURN l_claimed_time
END FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION startTask(l_empCode LIKE emp01.short_code, l_job_link INTEGER, l_work_code CHAR(4))
		RETURNS BOOLEAN
	DEFINE l_clock_time DATETIME YEAR TO SECOND

	LET l_clock_time = CURRENT

	DEBUG(2, SFMT("startTask: emp: %1 jl: %2 wc: %3", l_empCode, l_job_link, l_work_code))
-- Basic sanity checks
	IF l_empCode IS NULL THEN
		CALL dbLib_error("Invalid Employee Code!")
		RETURN FALSE
	END IF
	IF l_job_link IS NULL THEN
		CALL dbLib_error("Invalid Job Link!")
		RETURN FALSE
	END IF
	IF l_work_code IS NULL THEN
		CALL dbLib_error("Invalid Work Code!")
		RETURN FALSE
	END IF

	RETURN TRUE
END FUNCTION # Transaction_process
--------------------------------------------------------------------------------------------------------------
FUNCTION stopTask(l_empCode LIKE emp01.short_code, l_job_link INTEGER, l_work_code CHAR(4))
		RETURNS BOOLEAN
	DEFINE l_clock_time DATETIME YEAR TO SECOND
	DEBUG(2, SFMT("stopTask: emp: %1 jl: %2 wc: %3", l_empCode, l_job_link, l_work_code))

	LET l_clock_time = CURRENT

-- Basic sanity checks
	IF l_empCode IS NULL THEN
		CALL dbLib_error("Invalid Employee Code!")
		RETURN FALSE
	END IF
	IF l_job_link IS NULL THEN
		CALL dbLib_error("Invalid Job Link!")
		RETURN FALSE
	END IF
	IF l_work_code IS NULL THEN
		CALL dbLib_error("Invalid Work Code!")
		RETURN FALSE
	END IF

	RETURN TRUE
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- NOTE: Now not being used becuse we are using the  trimUpdateTask program instead.
FUNCTION completeTask(l_empCode LIKE emp01.short_code, l_job_link INTEGER, l_work_code CHAR(4))
		RETURNS BOOLEAN
	DEFINE l_clock_time DATETIME YEAR TO SECOND

	LET l_clock_time = CURRENT
	DEBUG(2, SFMT("completeTask: emp: %1 jl: %2 wc: %3", l_empCode, l_job_link, l_work_code))

-- Basic sanity checks
	IF l_empCode IS NULL THEN
		CALL dbLib_error("Invalid Employee Code!")
		RETURN FALSE
	END IF
	IF l_job_link IS NULL THEN
		CALL dbLib_error("Invalid Job Link!")
		RETURN FALSE
	END IF
	IF l_work_code IS NULL THEN
		CALL dbLib_error("Invalid Work Code!")
		RETURN FALSE
	END IF

	RETURN TRUE
END FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION checkTaskHeld(l_job_link INT, l_work_code LIKE trim1.work_code, l_complete BOOLEAN) RETURNS(BOOLEAN, STRING)
	DEFINE l_mess      STRING
	DEFINE l_held      BOOLEAN
	DEFINE l_who_by    STRING

	-- get the list_link
	DEBUG(2, SFMT("checkTaskHeld: jl: %1 wc: %2 comp: %3", l_job_link, l_work_code, l_complete))

	IF l_held THEN # Held From Starting
		LET l_mess = "Held By: ", l_who_by CLIPPED, "\n'", l_mess CLIPPED, "'"
	END IF
	RETURN l_held, l_mess.trim()
END FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION clearHold(l_job_link INT, l_work_code LIKE trim1.work_code, l_emp LIKE emp01.short_code)

	DEBUG(2, SFMT("clearHold: jl: %1 wc: %2 emp: %3", l_job_link, l_work_code, l_emp))
	-- get the list_link

END FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION execute(l_stmt STRING)
	DEBUG(2, SFMT("execute: PrepareStmt:\n%1", l_stmt))
	TRY
		PREPARE pre_ins FROM l_stmt
	CATCH
		DEBUG(0, SFMT("execute: PrepareStmt:\n%1\nError:%2", l_stmt, SQLERRMESSAGE))
		CALL dbLib_error("Database Prepare Error - see logs for details")
		RETURN FALSE
	END TRY
	TRY
		EXECUTE pre_ins
	CATCH
		DEBUG(0, SFMT("execute: ExecuteStmt:\n%1\nError:%2", l_stmt, SQLERRMESSAGE))
		CALL dbLib_error("Database Execute Error - see logs for details")
		RETURN FALSE
	END TRY
	DEBUG(2, "execute: Execute Done.")
	RETURN TRUE
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Returns the primary query SQL for selecting jobs
FUNCTION taskCursor(l_rows SMALLINT, l_age SMALLINT, l_branch CHAR(2)) RETURNS STRING
	DEFINE l_threshold       DATETIME YEAR TO FRACTION
	DEFINE l_q1              STRING
	DEFINE l_job_type        STRING = "%"
	DEFINE l_view_constraint CHAR(1) = "B"
	DEFINE l_which           CHAR(1) = "."
	DEFINE l_onsiteonly      CHAR(1) = "N" -- appently we don't car if the vehicle is 'onsite' or not.
	DEFINE l_usergroup       STRING
	LET l_threshold = CURRENT - l_age UNITS DAY

	DEBUG(2, SFMT("taskCursor: rows: %1 age: %2 branch: %3", l_rows, l_age, l_branch))

	LET l_q1 =
&ifdef OPTIMIZE1
			"SELECT --+AVOID_FULL(job01) ORDERED job01\n FIRST ", l_rows,
			" job01.job_number,job01.job_link FROM job01, job_dates, vehicle",
&else
   "SELECT --+AVOID_FULL(job01) ORDERED job01\n FIRST ", l_rows, " * FROM job01, job_dates, vehicle",
&endif
			" WHERE job01.job_link = job_dates.job_link AND job01.amended_date > \"", l_threshold CLIPPED, "\" AND ",
			" vehicle.vehicle_index = job01.vehicle_index"

	# In the interests of efficiency,  we won't just
	# " AND job01.job_type LIKE \"",m_job_type,"\" ",
	# but instead:
	IF l_job_type <> "%" THEN
		LET l_q1 = l_q1 CLIPPED, " AND job01.job_type = \"", l_job_type, "\" "
	END IF
	IF l_usergroup IS NOT NULL THEN
		LET l_q1 = l_q1 CLIPPED, " AND job01.group_code LIKE \"", (l_usergroup CLIPPED), "\""
	END IF
	IF l_branch != "%" THEN
		LET l_q1 = l_q1 CLIPPED, " AND job01.branch_code = \"", l_branch CLIPPED, "\""
	END IF
	###########################################################################
	#
	# Constraints
	#

	CASE l_view_constraint
		WHEN "A"
			# This Is Type "A"
			# Keep Until ws_complete
			LET l_q1 =
					l_q1 CLIPPED, " AND (in_progress IS NOT NULL OR user_live IS NOT NULL OR parts_ordered IS NOT NULL)",
					" AND ws_comp IS NULL"
		WHEN "B"
			# This Is Type "B"
			# Keep Until Handover To Customer
			LET l_q1 =
					l_q1 CLIPPED, " AND (in_progress IS NOT NULL OR user_live IS NOT NULL OR parts_ordered IS NOT NULL)",
					" AND handover IS NULL"
		WHEN "C"
			# Remove Once Invoiced
			LET l_q1 =
					l_q1 CLIPPED, " AND (in_progress IS NOT NULL OR user_live IS NOT NULL OR parts_ordered IS NOT NULL)",
					" AND invoiced IS NULL"
		WHEN "D"
			# Remove Once Invoiced And ws_complete
			LET l_q1 =
					l_q1 CLIPPED, " AND (in_progress IS NOT NULL OR user_live IS NOT NULL OR parts_ordered IS NOT NULL)",
					" AND (ws_comp IS NULL OR invoiced IS NULL)"
		WHEN "E"
			# Keep Until Handover To Customer Or WS Comp And Invoiced And OnSite = "N"
			LET l_q1 =
					l_q1 CLIPPED, " AND (in_progress IS NOT NULL OR user_live IS NOT NULL OR parts_ordered IS NOT NULL)",
					" AND NOT (handover IS NOT NULL OR (ws_comp IS NOT NULL AND invoiced IS NOT NULL AND on_site = \"N\"))"
		OTHERWISE
			CALL m_db_mobLib.exitProgram("Unknown View Constraint In Setup", 1) -- shouldn't happen!
	END CASE

	# But We Always Exclude Closed And Cancelled Jobs
	LET l_q1 = l_q1 CLIPPED, " AND job_closed IS NULL AND job_cancelled IS NULL"

	##############################################################################
	#
	# Deal With Status
	CASE l_which
		WHEN "a"
			# Allocated Jobs Only
			LET l_q1 = l_q1, " AND job01.job_link IN", " (SELECT UNIQUE job_link FROM next_job", " WHERE taken IS NULL)"
		WHEN "U"
			# UnAllocated Jobs Only
			LET l_q1 = l_q1, " AND job01.job_link NOT IN", " (SELECT UNIQUE job_link FROM next_job", " WHERE taken IS NULL)"
		WHEN "A"
			# Active Jobs
			LET l_q1 = l_q1, " AND job01.job_link IN (SELECT UNIQUE job_link", " FROM trim1 WHERE interrupt_time IS NULL)"
		WHEN "H"
			# Held Jobs
			LET l_q1 = l_q1, " AND job_dates.job_hold IS NOT NULL"
		WHEN "I"
			# Idle Jobs
			LET l_q1 = l_q1, " AND job01.job_link NOT IN (SELECT UNIQUE job_link", " FROM trim1)"
		WHEN "N"
			# Jobs Not Yet Started
			LET l_q1 = l_q1, " AND job_dates.in_progress IS NULL"
			#" AND job01.job_link NOT IN (SELECT UNIQUE job_link",
			#" FROM trim2a)"
	END CASE
	IF l_onsiteonly = "Y" THEN
		LET l_q1 = l_q1 CLIPPED, " AND job01.on_site = \"Y\""
	END IF

	LET l_q1 = l_q1 CLIPPED, " ORDER BY job_number"

	RETURN l_q1

END FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION getTaskData(
		l_branch CHAR(2), l_emp CHAR(4), l_rows SMALLINT, l_age SMALLINT, l_delivery INTEGER, l_collection INTEGER)
		RETURNS(DYNAMIC ARRAY OF t_listData1)
	DEFINE l_q1   STRING
	DEFINE l_data STRING
	DEFINE l_arr  DYNAMIC ARRAY OF t_listData1

	DEBUG(2, SFMT("getTaskData: Br:%1 E:%2 R:%3 A:%4 D:%5 C:%6", l_branch, l_emp, l_rows, l_age, l_delivery, l_collection))

	LET l_data = getData("getTasks_" || l_emp || ".json")
	IF l_data IS NOT NULL THEN
		CALL util.JSON.parse(l_data, l_arr)
		RETURN l_arr
	END IF

	LET l_q1 = taskCursor(l_rows: l_rows, l_age: l_age, l_branch: l_branch)
--	LET l_q1 = "SELECT 'jn', job_link FROM next_job WHERE employee = '",l_emp,"' AND branch = '",l_branch,"' ORDER BY job_link"
	DEBUG(2, l_q1)
	PREPARE statement1 FROM l_q1
	DECLARE sel_jobs SCROLL CURSOR FOR statement1
	RETURN getTasks(l_emp: l_emp, l_collection: l_collection, l_delivery: l_delivery)
END FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION getTasks(l_emp CHAR(4), l_collection INT, l_delivery INT) RETURNS(DYNAMIC ARRAY OF t_listData1)
	DEFINE l_job01     RECORD LIKE job01.*
	DEFINE l_job_dates RECORD LIKE job_dates.*
	DEFINE l_vehicle   RECORD LIKE vehicle.*
	DEFINE l_lista     RECORD LIKE lista.*
	DEFINE l_lists     RECORD LIKE lists.*
	DEFINE l_trim1     RECORD LIKE trim1.*
	DEFINE l_trim2     RECORD LIKE trim2.*
	DEFINE l_next      RECORD LIKE next_job.*
	DEFINE l_rec       t_listData1
	DEFINE l_arr       DYNAMIC ARRAY OF t_listData1
	DEFINE x           INTEGER
	DEFINE l_jobs      INTEGER = 1
	DEFINE l_tasks     INTEGER = 0
	DEFINE l_gotList   BOOLEAN
	DEFINE l_jn        LIKE job01.job_number
	DEFINE l_st        DATETIME MINUTE TO FRACTION(3)
	DEFINE l_jl        INTEGER

	IF l_emp IS NULL THEN
		LET l_emp = "...."
	END IF -- make sure we don't find any rows with ANY employee - ie unassigned rows only.
	DEBUG(2, SFMT("getTasks: %1 %2 %3", l_emp, l_delivery, l_collection))

	DECLARE sel_job CURSOR FOR
			SELECT * FROM job01, job_dates, vehicle
					WHERE job01.job_link = ? AND job_dates.job_link = job01.job_link
							AND vehicle.vehicle_index = job01.vehicle_index AND job_closed IS NULL AND job_cancelled IS NULL
							AND (in_progress IS NOT NULL OR user_live IS NOT NULL OR parts_ordered IS NOT NULL) AND handover IS NULL

	DECLARE sel_trim1 CURSOR FOR
			SELECT * FROM trim1
					WHERE job_link = l_job01.job_link AND trim1.work_code = l_lists.work_code AND employee_code = l_emp

	DECLARE sel_trim2 CURSOR FOR
			SELECT * FROM trim2
					WHERE job_link = l_job01.job_link AND trim2.work_code = l_lists.work_code AND employee_code = l_emp
					ORDER BY txn_date, txn_no

	DECLARE sel_next CURSOR FOR
			SELECT * FROM next_job
					WHERE job_link = l_job01.job_link AND next_job.task = l_lists.internal_no AND employee = l_emp
					ORDER BY priority DESC

	{Cursor To Read Task Status For Job Enquiry}
	DECLARE sel_tasks CURSOR FOR
			SELECT * FROM lista, lists
					WHERE lista.job_link = l_job01.job_link AND lista.entry_no = 0 AND lists.internal_no = lista.list_link
							AND lists.show_trim = "Y" AND lists.work_code IS NOT NULL AND p_status < 128 -- exclude completed tasks
					-- Apperently collection and delivery should be included now.
					--							AND lista.list_link != l_collection
					--							AND lista.list_link != l_delivery
					ORDER BY lists.list_no ASC
	LET x    = 1
	LET l_st = CURRENT
&ifdef OPTIMIZE1
	FOREACH sel_jobs INTO l_jn, l_jl
		OPEN sel_job USING l_jl
		FETCH sel_job INTO l_job01.*, l_job_dates.*, l_vehicle.*
		CLOSE sel_job
&else
 FOREACH sel_jobs INTO l_job01.*, l_job_dates.*, l_vehicle.*
&endif
		LET l_gotList = FALSE
		FOREACH sel_tasks INTO l_lista.*, l_lists.*
			LET l_gotList = TRUE
			IF l_lista.p_status >= 64 THEN # Task started
			END IF
			IF l_lista.p_status < 128 THEN # Task not completed
			END IF
			LET l_rec.branch_code  = l_job01.branch_code
			LET l_rec.job_number   = l_job01.job_number
			LET l_rec.job_link     = l_job01.job_link
			LET l_rec.veh_reg      = l_vehicle.vehicle_id
			LET l_rec.veh_make     = l_vehicle.make CLIPPED, " / ", l_vehicle.model_name CLIPPED
			LET l_rec.veh_colour   = l_vehicle.colour_name
			LET l_rec.contact      = l_job01.contact_name
			LET l_rec.work_code    = l_lists.work_code
			LET l_rec.list_title   = l_lists.list_title
			LET l_rec.list_status  = l_lista.p_status
			LET l_rec.sch_handover = l_job_dates.sched_handover
			LET l_rec.list_link    = l_lista.list_link
			LET l_rec.workshop_hrs = l_lista.workshop_hours
			LET l_rec.actual_hrs   = l_lista.actual_hours
			LET l_rec.emp_code     = "_"
			LET l_rec.trim_cmd     = "_"
			LET l_rec.trim_stop    = "_"
			LET l_rec.trim         = 0
			LET l_rec.priority     = 0
			LET l_rec.in_next_job  = FALSE
			LET l_rec.in_trim1     = FALSE
			LET l_rec.in_trim2     = FALSE

			DEBUG(3, SFMT("Job Dets %1) %2 %3/%4 For:%5", l_jobs, l_job01.job_number, l_vehicle.vehicle_id[1, 8], l_vehicle.model_name, l_job01.contact_name))
			DEBUG(3, SFMT("    List %1:%2:%3:%4", l_lista.list_link, l_lists.work_code, l_lists.list_no, l_lists.list_title))

-- Tasks assigned but maybe not started.
			FOREACH sel_next INTO l_next.*
				DEBUG(3, SFMT("        Found NextJob: %1 %2", l_job01.job_number, l_lists.work_code))
				LET l_rec.emp_code    = l_next.employee
				LET l_rec.started     = l_next.taken
				LET l_rec.priority    = l_next.priority
				LET l_rec.trim        = 3
				LET l_rec.state_desc  = "Not Started"
				LET l_rec.in_next_job = TRUE
			END FOREACH

-- started and stopped/paused/completed and maybe retarted
			FOREACH sel_trim2 INTO l_trim2.*
				DEBUG(3, SFMT("        Found Trim2: %1 %2", l_job01.job_number, l_lists.work_code))
				LET l_rec.emp_code   = l_trim2.employee_code
				LET l_rec.started    = l_trim2.start_datetime
				LET l_rec.stopped    = l_trim2.end_datetime
				LET l_rec.trim_cmd   = l_trim2.start_command
				LET l_rec.trim_stop  = l_trim2.stop_command
				LET l_rec.state_desc = getCommandDesc(l_rec.trim_stop)
				LET l_rec.trim       = 2
				LET l_rec.in_trim2   = TRUE
			END FOREACH

-- start event but never stopped/paused/completed
-- if we have trim1 record then the l_lista.actual_hours
			FOREACH sel_trim1 INTO l_trim1.*
				DEBUG(3, SFMT("        Found Trim1: %1 %2", l_job01.job_number, l_lists.work_code))
				LET l_rec.emp_code   = l_trim1.employee_code
				LET l_rec.started    = l_trim1.swipe_time
				LET l_rec.trim_cmd   = l_trim1.command_code
				LET l_rec.trim       = 1
				LET l_rec.state_desc = getCommandDesc(l_rec.trim_cmd)
				LET l_rec.in_trim1   = TRUE
			END FOREACH
			LET l_arr[x].* = l_rec.*
			IF l_arr[x].trim > 0 THEN
				LET l_tasks = l_tasks + 1
			END IF
			IF x > 1 THEN -- count the number of jobs.
				IF l_arr[x].job_number != l_arr[x - 1].job_number THEN
					LET l_jobs = l_jobs + 1
				END IF
			END IF
			LET x = x + 1
		END FOREACH
		IF NOT l_gotList THEN
			DEBUG(3, SFMT("NO LISTA for: %1:%2:%3:%4", l_job01.job_number, l_vehicle.vehicle_id, l_vehicle.model_name, l_job01.contact_name))
		END IF
	END FOREACH
	IF l_arr[x].job_number IS NULL THEN
		CALL l_arr.deleteElement(x)
	END IF
	LET m_jobsFound  = l_jobs
	LET m_tasksFound = l_tasks
	DEBUG(2, SFMT("Data found Jobs: %1 Tasks: %2: Arr: %3 in %4", l_jobs, l_tasks, l_arr.getLength(), CURRENT MINUTE TO FRACTION(3) - l_st))
	CALL l_arr.sort("priority", FALSE)
	FOR x = 1 TO l_arr.getLength()
		DEBUG(3, SFMT("%1 %2(%3) WC: %4 Cmd: %5 NJ: %6 T1: %7 T2: %8  PS: %9 Emp: %10 Srt: %11", l_arr[x].branch_code, l_arr[x].job_number, l_arr[x].job_link, l_arr[x].work_code, l_arr[x].trim_cmd, l_arr[x].in_next_job, l_arr[x].in_trim1, l_arr[x].in_trim2, (l_arr[x].list_status USING "&&#"), l_arr[x].emp_code, l_arr[x].started))
	END FOR

&ifdef DUMPDATA
	CALL dumpData("getTasks_" || l_emp || ".json", util.json.stringify(l_arr))
&endif

	RETURN l_arr
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Get a list of Task for a job.
FUNCTION timeRemaining(l_rec t_listData1) RETURNS DECIMAL(6, 2)
	DEFINE l_htime     INTERVAL DAY TO SECOND
	DEFINE l_htime_hrs INTERVAL HOUR(9) TO MINUTE
	DEFINE l_htime_dec DECIMAL(6, 2)
	DEFINE l_remaining DECIMAL(6, 2)
	DEFINE l_lista     RECORD LIKE lista.*
&ifdef NOUPD
	RETURN 1.2
&endif
-- Get the current lista details.
	SELECT * INTO l_lista.* FROM lista
			WHERE job_link = l_rec.job_link AND lista.entry_no = 0 AND lista.list_link = l_rec.list_link
	LET l_rec.workshop_hrs = l_lista.workshop_hours
	LET l_rec.actual_hrs   = l_lista.actual_hours
-- Time in progress from trim1 tasks. ( from f_bc_gen.4gl job_enquiry function )
	SELECT SUM(CURRENT - swipe_time) INTO l_htime FROM trim1
			WHERE trim1.job_link = l_rec.job_link AND trim1.work_code = l_rec.work_code AND trim1.interrupt_flag IS NULL
					AND trim1.interrupt_time IS NULL
	LET l_htime_hrs = l_htime
--	LET l_htime_dec = conv_time_to_dec_(l_htime_hrs)
	LET l_remaining = l_rec.workshop_hrs - l_rec.actual_hrs - l_htime_dec
	IF l_htime_dec != 0 THEN
		DEBUG(2, SFMT("Remain: %1 = wrk %2 - act %3 - t1 %4 ( htim: %5 )", l_rec.time_remaining, l_rec.workshop_hrs, l_rec.actual_hrs, l_htime_dec, l_htime))
	END IF
	RETURN l_remaining
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Put a file to cloud storage
FUNCTION putFileForJob(l_job_link LIKE job01.job_link, l_path STRING, l_file STRING) RETURNS BOOLEAN

	DEBUG(2, SFMT("putFileForJob: jl: %1 path: %2 file: %3", l_job_link, l_path, l_file ))

	CALL dbLib_error("Cloud Store not enabled.")
	RETURN FALSE
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Get a file from cloud storage
FUNCTION getFileForJob(l_job_link LIKE job01.job_link, l_path STRING, l_file STRING) RETURNS BOOLEAN

	DEBUG(2, SFMT("getFileForJob: jl: %1 path: %2 file: %3", l_job_link, l_path, l_file ))

	CALL dbLib_error("Cloud Store not enabled.")
	RETURN FALSE
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Get a documents / image list from local and cloud storage
FUNCTION getDocsForJob(l_job_link LIKE job01.job_link, l_dir1 STRING, l_dir2 STRING)
	DEFINE l_arr DYNAMIC ARRAY OF RECORD
		line1       STRING,
		line2       STRING,
		line_img    STRING,
		cf_or_local CHAR(1)
	END RECORD
	DEFINE l_ext      STRING
	DEFINE l_handle   INTEGER
	DEFINE l_path     STRING
	DEFINE x SMALLINT

	DEBUG(3, SFMT("getDocsForJob: 1: %1 2: %2", l_dir1, l_dir2))

	CALL os.Path.dirSort("name", 1)
	LET l_handle = os.Path.dirOpen(l_dir1)
	LET x        = 0
	IF l_handle > 0 THEN
		WHILE TRUE
			LET l_path = os.Path.dirNext(l_handle)
			IF l_path IS NULL THEN
				EXIT WHILE
			END IF

			IF os.Path.isDirectory(l_path) THEN
				--DISPLAY "Dir:",path
				CONTINUE WHILE
			ELSE
				--DISPLAY "Fil:",path
			END IF

			LET l_ext = os.Path.extension(l_path).toLowerCase()
			IF l_ext IS NULL OR (l_ext != C_DOCEXT AND l_ext != C_IMGEXT AND l_ext != C_PDFEXT) THEN
				CONTINUE WHILE
			END IF

			IF NOT l_path MATCHES ("*" || l_job_link || "_*") THEN
				CONTINUE WHILE
			END IF

			LET x                    = x + 1
			LET l_arr[x].line1       = l_path
			LET l_arr[x].cf_or_local = "L"
			CALL setFileType(l_ext) RETURNING l_arr[x].line_img, l_arr[x].line2
		END WHILE
	END IF

	LET l_handle = os.Path.dirOpen(l_dir2)
	IF l_handle > 0 THEN
		WHILE TRUE
			LET l_path = os.Path.dirNext(l_handle)
			IF l_path IS NULL THEN
				EXIT WHILE
			END IF

			IF os.Path.isDirectory(l_path) THEN
				--DISPLAY "Dir:",path
				CONTINUE WHILE
			ELSE
				--DISPLAY "Fil:",path
			END IF

			LET l_ext = os.Path.extension(l_path).toLowerCase()
			IF l_ext IS NULL OR (l_ext != C_DOCEXT AND l_ext != C_IMGEXT AND l_ext != C_PDFEXT) THEN
				CONTINUE WHILE
			END IF

			IF NOT l_path MATCHES ("*" || l_job_link || "_*") THEN
				CONTINUE WHILE
			END IF

			LET x                    = x + 1
			LET l_arr[x].line1       = l_path
			LET l_arr[x].cf_or_local = "L"
			CALL setFileType(l_ext) RETURNING l_arr[x].line_img, l_arr[x].line2
		END WHILE
	END IF

	RETURN l_arr
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Get a list of Parts/sublet for a job.
FUNCTION setFileType(l_ext STRING) RETURNS(STRING, STRING)
	DEFINE l_type, l_desc STRING
	CASE l_ext
		WHEN C_PDFEXT
			LET l_desc = "PDF Document"
			LET l_type = "pdf"
		WHEN C_DOCEXT
			LET l_desc = "Document"
			LET l_type = "doc"
		WHEN C_IMGEXT
			LET l_desc = "Image"
			LET l_type = "img"
		OTHERWISE
			LET l_desc = "Unknown"
			LET l_type = "unk"
	END CASE
	RETURN l_type, l_desc
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Get a list of Parts/sublet for a job.
FUNCTION productJobSheet(l_branch LIKE bra01.branch_code, l_user_id CHAR(10), l_job_link LIKE job01.job_link)
		RETURNS SMALLINT
	DEFINE l_args STRING
	DEFINE l_ret  SMALLINT
	LET l_args = SFMT("%1 %2 %3", l_branch, l_user_id, l_job_link)
	LET l_ret  = runProg("print_jobsheet", l_args)
	RETURN l_ret
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Get a list of Parts/sublet for a job.
FUNCTION getPartsForJob(l_job_link LIKE job01.job_link)
	DEFINE l_arr DYNAMIC ARRAY OF RECORD
		line1    STRING,
		line2    STRING,
		line_img STRING
	END RECORD
	DEFINE l_data          STRING

	DEBUG(2, SFMT("getPartsForJob: JL: %1", l_job_link))
	LET l_data = getData("getPartsForJob_" || l_job_link || ".json")
	IF l_data IS NOT NULL THEN
		CALL util.JSON.parse(l_data, l_arr)
		RETURN l_arr
	END IF

--TODO: getData

	DEBUG(2, SFMT("getPartsForJob: JL: %1 Rows: %2", l_job_link, l_arr.getLength()))
&ifdef DUMPDATA
	CALL dumpData("getPartsForJob_" || l_job_link || ".json", util.JSON.stringify(l_arr))
&endif
	RETURN l_arr
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Get a list of Task for a job.
FUNCTION getTasksForJob(l_job_link LIKE job01.job_link)
	DEFINE l_arr DYNAMIC ARRAY OF RECORD
		line1    STRING,
		line2    STRING,
		line_img STRING
	END RECORD
	DEFINE l_data        STRING

	DEBUG(2, SFMT("getTasksForJob JL: %1", l_job_link))

	LET l_data = getData("getTasksForJob_" || l_job_link || ".json")
	IF l_data IS NOT NULL THEN
		CALL util.JSON.parse(l_data, l_arr)
		RETURN l_arr
	END IF

--TODO: getData

&ifdef DUMPDATA
	CALL dumpData("getTasksForJob_" || l_job_link || ".json", util.JSON.stringify(l_arr))
&endif
	RETURN l_arr
END FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION getTaskStatus(
		l_p_status INTEGER, l_running BOOLEAN, l_started BOOLEAN, l_overrun BOOLEAN, l_is_allocated BOOLEAN)
		RETURNS(STRING, STRING)
	DEFINE l_status            STRING
	DEFINE l_lamp, f_attribute STRING

	IF l_p_status < 128 # bit 8
			THEN {Task Not Flagged Completed}
		IF l_running THEN {TRIM ACTIVE SO YELLOW, REVERSE = OVERRUN}
			IF l_overrun THEN
				# In progress Overunning
				LET l_lamp      = "trim_status_amber_over"
				LET f_attribute = "#ff8000 reverse"
				LET l_status    = "In progress & Overrunning"
			ELSE
				# In progress On Schedule
				LET l_lamp      = "trim_status_amber"
				LET f_attribute = "#ffd18c reverse"
				LET l_status    = "In Progress & On Schedule"
			END IF
		ELSE {CURRENTLY IDLE, CYAN REVERSE, REVERSE = OVERRUN}
			IF l_overrun THEN
				# idle overrun
				LET l_lamp      = "trim_status_blue_over"
				LET f_attribute = "#0066ff reverse"
				LET l_status    = "Idle & Overrunning"
			ELSE
				IF l_started THEN
					# idle
					LET l_lamp      = "trim_status_blue"
					LET f_attribute = "#9fc6ff reverse"
					LET l_status    = "Idle"
				ELSE
					LET l_lamp      = "trim_status_white"
					LET f_attribute = "#e0e0e0 reverse"
					LET l_status    = "Not Started"
					IF l_is_allocated THEN
						LET l_lamp      = "trim_status_yellow"
						LET f_attribute = "#ffff00 reverse"
						LET l_status    = "Allocated"
					END IF
				END IF
			END IF
		END IF
	ELSE {Task Flagged Completed}
		IF l_running THEN {Task Complete And Still Running}
			IF l_overrun THEN {Task Complete, Running And Overrun}
				LET l_lamp      = "trim_status_pink_over" # restart overrun
				LET l_status    = "Restarted & Overrunning"
				LET f_attribute = "#b500e1 reverse"
			ELSE {Task Complete Running, But Not Overrun}
				LET l_lamp      = "trim_status_pink"
				LET f_attribute = "#ec9dff reverse"
				LET l_status    = "Restarted & Still On Schedule"
			END IF
		ELSE {Task Complete, Not Running}
			IF l_overrun THEN {Task Complete But Overrun}
				LET l_lamp      = "trim_status_green_over"
				LET f_attribute = "#006600 reverse"
				LET l_status    = "Completed & Overran"
			ELSE {Task Complete But Not Overrun}
				LET l_lamp      = "trim_status_green"
				LET f_attribute = "#99cc00 reverse"
				LET l_status    = "Completed On Schedule"
			END IF
		END IF
	END IF
	RETURN l_status, l_lamp
END FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION isClockedOn(l_empCode LIKE trim1.employee_code)
		RETURNS(BOOLEAN, LIKE trim1.swipe_time)
	DEFINE l_count SMALLINT
	DEFINE l_dt    LIKE trim1.swipe_time
	DEBUG(2, SFMT("isClockedOn: emp: %1", l_empCode))


	RETURN (l_count > 0), l_dt
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Return the description for the command_code value
FUNCTION getCommandDesc(l_cmd CHAR(1)) RETURNS STRING
	DEFINE l_desc STRING
	IF l_cmd IS NULL THEN
		LET l_cmd = " "
	END IF
	CASE l_cmd
		WHEN " "
			LET l_desc = "No Status Yet"
		WHEN "X"
			LET l_desc = "Clock On"
		WHEN "Y"
			LET l_desc = "Clock Off"
		WHEN "S"
			LET l_desc = "Started / Resumed"
		WHEN "E"
			LET l_desc = "Ended"
		WHEN "K"
			LET l_desc = "Task Complete"
		WHEN "H"
			LET l_desc = "Interrupted"
		WHEN "P"
			LET l_desc = "Suspended"
		WHEN "J"
			LET l_desc = "Job Complete"
		WHEN "N"
			LET l_desc = "MISC CLOCK OFF"
		WHEN "M"
			LET l_desc = "MISC CLOCK ON"
		WHEN "L"
			LET l_desc = "Employee Enquiry"
		WHEN "Q"
			LET l_desc = "Job Enquiry"
		WHEN "Z"
			LET l_desc = "Clock Off And Task End"
		WHEN "A"
			LET l_desc = "ATA Sign Off"
		WHEN "G"
			LET l_desc = "Auto restarted after clockoff"
		OTHERWISE
			LET l_desc = SFMT("%1: %2", l_cmd, "Unknown!")
	END CASE
	RETURN l_desc
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Run an eclipse program
FUNCTION runProg(l_prog STRING, l_args STRING) RETURNS SMALLINT
	DEFINE l_dir           STRING
	DEFINE l_progDir       STRING
	DEFINE l_cmd, l_genero STRING
	DEFINE l_ret           SMALLINT
	DEFINE l_result        STRING
	DEFINE c               base.Channel
-- check release dir exists
	LET l_dir = os.Path.join(m_db_mobLib.cfg.baseDir, m_db_mobLib.sysName)
	IF NOT os.Path.exists(l_dir) THEN
		CALL stdLib.error(SFMT("Folder not found '%1'", l_dir), TRUE)
		RETURN -1
	END IF

-- check generorun.sh exists
	IF NOT os.Path.exists("generorun.sh") THEN
		CALL stdLib.error("generorun.sh not found!", TRUE)
		RETURN -1
	END IF

-- check program exists
	IF NOT os.Path.exists(os.Path.join(l_dir, l_prog || ".42r")) THEN
		CALL stdLib.error(SFMT("Program '%1' not found", l_prog), TRUE)
		RETURN -1
	END IF

-- Genero
	LET l_genero = SFMT("/opt/fourjs/fgl%1", m_db_mobLib.eclipseGenVer)
	IF NOT os.Path.exists(l_genero) THEN
		CALL stdLib.error(SFMT("Failed to find '%1'", l_genero), TRUE)
		RETURN -1
	END IF

	DEBUG(3, SFMT("runProg: Now in %1", l_dir))
-- set env and run program
	LET l_progDir = os.Path.join(m_db_mobLib.cfg.baseDir, m_db_mobLib.sysName)

	CALL fgl_setenv("DBNAME", m_db_mobLib.dbName)
	CALL fgl_setenv("LOGNAME", m_db_mobLib.user_id)
	CALL fgl_setenv("CONO", m_db_mobLib.reg.cono)
	CALL fgl_setenv("BASEDIR", m_db_mobLib.cfg.baseDir)
	CALL fgl_setenv("SYSNAME", m_db_mobLib.sysName)
	CALL fgl_setenv("PROGDIR", l_progDir)
	CALL fgl_setenv("DATADIR", m_db_mobLib.cfg.fileStorage)
	CALL fgl_setenv("TRIMDOCS", m_db_mobLib.cfg.docPath)
	CALL fgl_setenv("FGLPROFILE", NULL)

	LET l_cmd =
			SFMT("./generorun.sh %1 %2 %3.run %4.42r %5",
					m_db_mobLib.eclipseGenVer, l_dir, stdLib.m_debugFile, l_prog, l_args)
	DEBUG(3, SFMT("runProg: in %1", os.Path.pwd()))
	DEBUG(3, SFMT("runProg: run: %1", l_cmd))
	LET c = base.Channel.create()
	CALL c.openPipe(l_cmd, "r")
	WHILE NOT c.isEof()
		LET l_result = l_result.append(c.readLine())
	END WHILE
	CALL c.close()
	IF l_result != "Okay" THEN
		CALL stdLib.error(SFMT("Run: %1\nFailed: %2 %3", l_cmd, l_ret, l_result), TRUE)
	END IF
	DEBUG(3, SFMT("runProg: Returned %1 %2", l_ret, l_result))

	RETURN l_ret
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Get Message of the Day
FUNCTION getMOD() RETURNS STRING
	DEFINE l_file STRING
	DEFINE l_txt  TEXT
	LET l_file = os.Path.join(m_db_mobLib.cfg.cfgPath, "mod.txt")
	IF NOT os.Path.exists(l_file) THEN
		DEBUG(1, SFMT("No Message of the Day file: %1", l_file))
		RETURN NULL
	END IF
	LOCATE l_txt IN FILE l_file
	DEBUG(1, SFMT("Message of the Day file: %1\nMOD: %2", l_file, l_txt))
	RETURN l_txt
END FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION getData(l_file STRING) RETURNS(STRING)
	DEFINE l_dump TEXT
	--DEBUG: dump task list to a JSON file for debug only.
	IF os.Path.exists(l_file) THEN
		LOCATE l_dump IN FILE l_file
		DISPLAY "Using: ", l_file
	ELSE
		RETURN NULL
	END IF
	RETURN l_dump
END FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION dumpData(l_file STRING, l_data STRING)
	DEFINE l_dump TEXT
	--DEBUG: dump task list to a JSON file for debug only.
	IF NOT os.Path.exists(l_file) THEN
		LOCATE l_dump IN FILE l_file
		LET l_dump = l_data
	END IF
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Error handler
FUNCTION dbLib_error(l_msg STRING)
	LET m_lastError = l_msg
	CALL stdLib.error(l_msg, m_doPopups)
END FUNCTION
