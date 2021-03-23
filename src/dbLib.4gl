IMPORT util
IMPORT os
IMPORT security
IMPORT FGL stdLib
IMPORT FGL mobLib

SCHEMA bsdb

CONSTANT C_DOCEXT = "doc"
CONSTANT C_PDFEXT = "pdf"
CONSTANT C_IMGEXT = "jpg"

&define DEBUG( l_lev, l_msg ) IF m_db_moblib.cfg.debug THEN CALL stdLib.debugOut( l_lev, __FILE__, __LINE__, l_msg ) END IF

-- uncomment to disable update/delete from database.
&define NOUPD 1
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
PUBLIC DEFINE m_db_moblib  mobLib
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
						"CREATE TABLE mobdemoreg( app_name VARCHAR(20), dev_id VARCHAR(30), ip VARCHAR(80), cono CHAR(4),user_id CHAR(10), when_ts DATETIME YEAR TO SECOND)"
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
	IF l_user.subString(1,4) = "test" AND l_pwd = "test" AND m_db_moblib.cfg.allowTest THEN
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
	DEBUG(3, SFMT("checkPassword: allowTest %1", m_db_moblib.cfg.allowTest))
	IF l_pass = "test" AND m_db_moblib.cfg.allowTest AND l_emp THEN
		RETURN TRUE
	END IF -- TODO: remove before go live!!
--	DEBUG(3, SFMT("PWD: %1 vs %2", l_pass.trim(), l_hash.trim()))
	TRY
		IF NOT Security.BCrypt.CheckPassword(l_pass.trim(), l_hash.trim()) THEN
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
		RETURN l_emp.*
	END IF
	DEBUG(2, SFMT("getEmployee: %1 @ %2 Okay", l_empCode, l_branch))

	IF l_pwd IS NULL THEN
		RETURN l_emp.*
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
			CALL stdLib.error("Invalid Login Details", TRUE)
			INITIALIZE l_emp TO NULL
			RETURN l_emp.*
		END IF
	ELSE
		IF l_pwd != "test" THEN
			INITIALIZE l_emp TO NULL
		END IF
		CALL stdLib.error("Your account is not setup for this application.\nContact the main office.", TRUE)
		-- TODO: when testing finished this error will be fatal and return NULL - for now allow it to pass
	END IF

	RETURN l_emp.*
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
		IF l_logged_in = "Y" AND l_last_dev_id != m_db_moblib.reg.dev_id2 THEN
			DEBUG(0, SFMT("%1 Already logged in %2 since %3", l_empCode, l_last_dev_id, l_last_login))
			RETURN SFMT("You are already logged in on another device\nSince %1", l_last_login)
		END IF
		LET l_last_login = CURRENT
		UPDATE device_login SET (last_dev_id, last_dev_id2, last_dev_ip, last_ip, last_login, failed_attempts, logged_in)
				= (m_db_moblib.reg.dev_id, m_db_moblib.reg.dev_id2, m_db_mobLib.reg.dev_ip, m_db_moblib.cli_ip, l_last_login, 0, "Y")
				WHERE emp_user = l_empCode AND branch_code = l_branch AND app_name = m_db_mobLib.appName
	ELSE
		LET l_last_login = CURRENT
		UPDATE device_login SET (logged_in, last_logout, logout_method) = ("N", l_last_login, l_method)
				WHERE emp_user = l_empCode AND branch_code = l_branch AND app_name = m_db_mobLib.appName
	END IF
	RETURN NULL
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Returns TRUE/FALSE for the clock on event and the number of active tasks restarted.
FUNCTION clockOn(l_emp RECORD LIKE emp01.*) RETURNS(BOOLEAN, SMALLINT)
	DEFINE l_trim1      RECORD LIKE trim1.*
	DEFINE l_active     SMALLINT
	DEFINE l_rowId      INTEGER
	DEFINE l_clock_time LIKE trim1.swipe_time

&ifdef NOUP
 DEBUG(0,"clockOn: NOUPD defined - not updating database!")
 RETURN TRUE, 0
&endif

	LET l_clock_time = CURRENT
	INITIALIZE l_trim1.* TO NULL
	LET l_trim1.weighting     = l_emp.weighting
	LET l_trim1.employee_code = l_emp.short_code
	LET l_trim1.branch_code   = l_emp.branch_code
	LET l_trim1.work_code     = "__ON"
	LET l_trim1.command_code  = "X"
	LET l_trim1.job_link      = 0
	LET l_trim1.swipe_time    = l_clock_time
	DEBUG(2, "clockOn: Insert trim1  record")
	BEGIN WORK
	TRY
		INSERT INTO trim1 VALUES(l_trim1.*)
	CATCH
	END TRY
	IF STATUS != 0 THEN
		DEBUG(0, SFMT("clockOn: Insert trim1 Failed: %1:%2", STATUS, SQLERRMESSAGE))
		CALL dbLib_error("clockOn: Trim1 Insert failed - see logs for details")
		RETURN FALSE, 0
	END IF

	IF l_emp.productive = "N" THEN -- should never get this far! can be Y or O(driver/valet)
		COMMIT WORK
		RETURN TRUE, 0
	END IF

-- Taken from r_trim_man_post.4gl : FUNCTION clock_on
-- Restart Any Tasks Interrupted By Clock Off
-- LEGACY: As trim1 has such a complex key,  best to use rowid
	DECLARE clock_on CURSOR FOR
			SELECT ROWID, * FROM trim1
					WHERE trim1.employee_code = l_emp.short_code AND trim1.branch_code = l_emp.branch_code
							AND trim1.command_code <> "X" -- Not clock On
							AND trim1.command_code <> "H" -- Not Interruption Task
							AND trim1.command_code <> "P" -- Not Suspended
							AND trim1.work_code <> "__ON" -- Not clock On
	LET l_active = 0
	FOREACH clock_on INTO l_rowId, l_trim1.*
		DEBUG(2, SFMT("clockOn: Restarting task: %1 - %2", l_trim1.job_link, l_trim1.work_code))
		LET l_active = l_active + 1
		INITIALIZE l_trim1.interrupt_flag TO NULL
		INITIALIZE l_trim1.interrupt_time TO NULL
		LET l_trim1.command_code = "G"
		LET l_trim1.swipe_time   = l_clock_time + 1 UNITS SECOND
		UPDATE trim1 SET trim1.* = l_trim1.* WHERE ROWID = l_rowId
	END FOREACH
	COMMIT WORK

	RETURN TRUE, l_active
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Apperently Suspended & Interruption are still 'active'
FUNCTION activeTasks(l_empCode LIKE emp01.short_code, l_branch LIKE emp01.branch_code) RETURNS(SMALLINT, SMALLINT)
	DEFINE l_count1 SMALLINT
	DEFINE l_count2 SMALLINT
	DEFINE l_count3 SMALLINT
	DEFINE l_jl, x  INTEGER
	DEFINE l_wc     LIKE trim2.work_code
	SELECT COUNT(*) INTO l_count1 FROM trim1
			WHERE trim1.employee_code = l_empCode AND trim1.branch_code = l_branch
					AND trim1.command_code <> "X" -- Not clock On
					--AND trim1.command_code <> "H" -- Not Interruption Task
					--AND trim1.command_code <> "P" -- Not Suspended
					AND trim1.work_code <> "__ON" -- Not clock On
-- Here we need to count the number of trim2 tasks for the employee that are not completed,
-- NOTE we need to link in 'lasta' to catch tasks we worked on but completed by someone else.
	DECLARE act_cur CURSOR FOR
			SELECT UNIQUE trim2.job_link, trim2.work_code, COUNT(*) FROM trim2, lista, lists
					WHERE trim2.employee_code = l_empCode AND trim2.branch_code = l_branch AND trim2.work_code IS NOT NULL
							AND trim2.stop_command != "K" -- not competed by this employee
							AND lists.work_code = trim2.work_code AND lista.job_link = trim2.job_link
							AND lista.list_link = lists.internal_no AND lista.entry_no = 0
							AND lista.p_status < 128 -- not completed by any employee
					GROUP BY 1, 2
	LET l_count2 = 0
	FOREACH act_cur INTO l_jl, l_wc
		IF l_wc IS NULL THEN
			CONTINUE FOREACH
		END IF
		SELECT COUNT(*) INTO x FROM trim1
				WHERE trim1.job_link = l_jl AND trim1.work_code = l_wc AND trim1.employee_code = l_empCode
		IF x = 0 THEN
			LET l_count2 = l_count2 + 1
		END IF
	END FOREACH

	SELECT COUNT(*) INTO l_count3 FROM next_job
			WHERE employee = l_empCode AND taken IS NULL

	DEBUG(3, SFMT("activeTasks: count1: %1 (trim1) count2: %2 (trim2) count3: %3 (next_job)", l_count1, l_count2, l_count3))
	RETURN l_count1 + l_count2, l_count3
END FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION claimedTime(l_empCode LIKE emp01.short_code) RETURNS(DECIMAL(10, 2), DECIMAL(10, 2), DECIMAL(10, 2))
	DEFINE l_claim_mtd, l_claim_wtd, l_claim_today DECIMAL(10, 2)

	CALL getClaimedTime(l_empCode, TODAY, TODAY) RETURNING l_claim_today
	CALL getClaimedTime(l_empCode, TODAY - WEEKDAY(TODAY) + 1, TODAY) RETURNING l_claim_wtd
	CALL getClaimedTime(l_empCode, TODAY - DAY(TODAY) + 1, TODAY) RETURNING l_claim_mtd

	RETURN l_claim_mtd, l_claim_wtd, l_claim_today
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Do the SQL's to actually get the claimed time
FUNCTION getClaimedTime(l_empCode LIKE emp01.short_code, l_start_date DATE, l_end_date DATE)
	DEFINE l_claimed_time1 DECIMAL(10, 2)
	DEFINE l_claimed_time2 DECIMAL(10, 2)

	SELECT SUM(claimed) INTO l_claimed_time1 FROM trim2
			WHERE trim2.employee_code = l_empCode AND trim2.start_command <> "X"
					AND trim2.txn_date BETWEEN l_start_date AND l_end_date

	SELECT SUM(claimed) INTO l_claimed_time2 FROM trim2b
			WHERE trim2b.employee_code = l_empCode AND trim2b.start_command <> "X"
					AND trim2b.txn_date BETWEEN l_start_date AND l_end_date

	IF l_claimed_time1 IS NULL THEN
		LET l_claimed_time1 = 0
	END IF
	IF l_claimed_time2 IS NULL THEN
		LET l_claimed_time2 = 0
	END IF

	RETURN l_claimed_time1 + l_claimed_time2
END FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION clockOff(l_emp RECORD LIKE emp01.*) RETURNS BOOLEAN
	DEFINE l_trim1      RECORD LIKE trim1.*
	DEFINE l_trim2      RECORD LIKE trim2.*
	DEFINE l_clock_time LIKE trim1.swipe_time
	DEFINE l_rowId      INTEGER

&ifdef NOUPD
 DEBUG(0,"clockOff: NOUPD defined - not updating database!")
 RETURN TRUE
&endif

	LET l_clock_time = CURRENT

	SELECT * INTO l_trim1.* FROM trim1
			WHERE trim1.employee_code = l_emp.short_code AND trim1.branch_code = l_emp.branch_code
					AND trim1.work_code = "__ON" AND trim1.command_code = "X"
	IF STATUS = NOTFOUND THEN -- Not clock on ?
		RETURN FALSE
	END IF

-- Insert Clock On Command Into trim2
	INITIALIZE l_trim2.* TO NULL
	LET l_trim2.actual_time    = 0
	LET l_trim2.txn_date       = TODAY
	LET l_trim2.txn_period     = 0
	LET l_trim2.start_datetime = l_trim1.swipe_time
-- Advance By 2 Seconds
	LET l_trim2.end_datetime  = l_clock_time + 2 UNITS SECOND
	LET l_trim2.interval_time = l_trim2.end_datetime - l_trim2.start_datetime
	LET l_trim2.decimal_time  = 0 --conv_time_to_dec_(l_trim2.interval_time)
	LET l_trim2.actual_cost   = 0
	LET l_trim2.job_link      = 0
	LET l_trim2.weighting     = l_trim1.weighting
	LET l_trim2.employee_code = l_emp.short_code
	LET l_trim2.branch_code   = l_emp.branch_code
	LET l_trim2.start_command = "X"
	LET l_trim2.stop_command  = "Y"
	LET l_trim2.txn_no        = 0

	DEBUG(2, "clockOff: Insert trim2 record.")
	BEGIN WORK
	INSERT INTO trim2 VALUES(l_trim2.*)
	LET l_trim2.txn_no = SQLCA.SQLERRD[2]
-- Insert Mirror File
	INSERT INTO trim2a VALUES(l_trim2.*)

-- Here Insert Clock Off Marker Into trim2}
-- Set Clock Of Time Same As Time In Clock On Marker}
	LET l_trim2.start_datetime = l_trim2.end_datetime
	LET l_trim2.end_datetime   = l_trim2.start_datetime
	LET l_trim2.decimal_time   = 0
	LET l_trim2.actual_cost    = 0
	LET l_trim2.interval_time  = "00:00"
	LET l_trim2.start_command  = "Y"
	LET l_trim2.txn_no         = 0
	INSERT INTO trim2 VALUES(l_trim2.*)
	LET l_trim2.txn_no = SQLCA.SQLERRD[2]
-- Insert Mirror File
	INSERT INTO trim2a VALUES(l_trim2.*)

-- Remove trim1 record
	DEBUG(2, "clockOff: Removing trim1 record")
	DELETE FROM trim1
			WHERE trim1.employee_code = l_emp.short_code AND trim1.branch_code = l_emp.branch_code
					AND trim1.work_code = "__ON" AND trim1.command_code = "X"

{ Here Handle Interrupting Tasks By Clocking Off
  We Have To Read Every Task In Trim1, Update interrupt
  Flag & Time But Leave trim1, Write Away To Trim2
  Then Write Clock Off To Trim2, When We Clock Back On
  The Suspended Tasks Are Restarted After Clock On Written
  To Trim2 Wow If This Works We Are Half Way To Hell}

	DECLARE clock_off CURSOR FOR
			SELECT ROWID, * FROM trim1
					WHERE trim1.employee_code = l_emp.short_code AND trim1.branch_code = l_emp.branch_code
							AND trim1.command_code <> "P" AND trim1.command_code <> "H"
	FOREACH clock_off INTO l_rowId, l_trim1.*
		DEBUG(2, SFMT("clockOff: Interrupting task: %1 - %2", l_trim1.job_link, l_trim1.work_code))
		LET l_trim1.interrupt_flag = "Y"
		LET l_trim1.interrupt_time = l_clock_time + 2 UNITS SECOND
		UPDATE trim1 SET trim1.* = l_trim1.* WHERE ROWID = l_rowId
	END FOREACH
	COMMIT WORK

	RETURN TRUE
END FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION startTask(l_emp RECORD LIKE emp01.*, l_job_link INTEGER, l_work_code CHAR(4), l_dt DATETIME YEAR TO SECOND)
		RETURNS BOOLEAN
	DEFINE l_trim1       RECORD LIKE trim1.*
	DEFINE l_list_link   INTEGER
	DEFINE l_in_progress DATE
	DEFINE l_command     CHAR(1)
	DEFINE l_args        STRING
	DEFINE l_ret         SMALLINT
	DEFINE l_p_status    LIKE lista.p_status
	DEFINE l_lista_trim  RECORD LIKE lista_trim.*

&ifdef NOUPD
 DEBUG(0,"startTask: NOUPD defined - not updating database!")
 RETURN TRUE
&endif

	DEBUG(2, SFMT("startTask: %1:%2:%3:%4", l_emp.branch_code, l_emp.short_code, l_job_link, l_work_code))
-- Basic sanity checks
	IF l_emp.short_code IS NULL THEN
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

-- Look to see if the trim1 record already exists.
	INITIALIZE l_trim1 TO NULL
	SELECT * INTO l_trim1.* FROM trim1
			WHERE trim1.work_code = l_work_code AND trim1.job_link = l_job_link AND trim1.employee_code = l_emp.short_code
					AND trim1.branch_code = l_emp.branch_code
	IF l_trim1.command_code = "K" THEN
		CALL dbLib_error("Task already completed!")
		RETURN FALSE
	END IF
	IF l_trim1.command_code MATCHES "[SG]" THEN -- Started / Autostarted after clock on
		CALL dbLib_error("Task already started!")
		RETURN FALSE
	END IF
	IF STATUS != NOTFOUND THEN
		CALL dbLib_error("Task already in trim1!") -- Shouldn't happen ?
		RETURN FALSE
	END IF

	SELECT internal_no INTO l_list_link FROM lists WHERE @work_code = l_work_code
	IF STATUS = NOTFOUND THEN
		CALL dbLib_error(SFMT("Task '%1' not found in lists!", l_work_code)) -- Shouldn't happen ?
		RETURN FALSE
	END IF

{
	LET l_command = "S"
	LET l_args = SFMT("%1 %2 %3 %4 %5", l_branch, l_emp_code, l_job_link, l_work_code, l_command)
	LET l_ret  = m_mobLib.runProg("trimUpdateTask", l_args)
	IF l_ret != 0 THEN
		CALL dbLib_error("Failed to Start task!" )
		RETURN FALSE
	END IF
}

	INITIALIZE l_trim1.* TO NULL
	LET l_trim1.weighting     = l_emp.weighting
	LET l_trim1.employee_code = l_emp.short_code
	LET l_trim1.branch_code   = l_emp.branch_code
	LET l_trim1.job_link      = l_job_link
	LET l_trim1.work_code     = l_work_code
	LET l_trim1.command_code  = "S"
	LET l_trim1.swipe_time    = l_dt

	DEBUG(2, "startTask: Insert trim1 record")
	TRY
		INSERT INTO trim1 VALUES(l_trim1.*)
	CATCH
	END TRY
	IF STATUS != 0 THEN
		DEBUG(0, SFMT("startTask: Insert trim1 Failed: %1:%2", STATUS, SQLERRMESSAGE))
		CALL dbLib_error("Trim1 Insert failed - see logs for details")
		RETURN FALSE
	END IF

	CALL create_lista_trim2(l_job_link, l_list_link, l_work_code) RETURNING l_lista_trim.*
	IF l_lista_trim.task_start IS NULL THEN
		UPDATE lista_trim SET lista_trim.task_start = CURRENT
				WHERE lista_trim.job_link = l_job_link AND lista_trim.list_link = l_list_link
	END IF

	SELECT p_status INTO l_p_status FROM lista
			WHERE lista.job_link = l_job_link AND lista.list_link = l_list_link AND lista.entry_no = 0
	IF STATUS = NOTFOUND THEN
		DEBUG(2, "startTask: lista record not found!")
	ELSE
		LET l_p_status = 64
		UPDATE lista SET lista.p_status = l_p_status
				WHERE lista.job_link = l_job_link AND lista.list_link = l_list_link AND lista.entry_no = 0
	END IF

	SELECT in_progress INTO l_in_progress FROM job_dates WHERE job_link = l_job_link
	IF l_in_progress IS NULL THEN
		UPDATE job_dates SET (in_progress, in_progress1) = (l_dt, l_dt) WHERE job_link = l_job_link
	END IF

	RETURN TRUE
END FUNCTION # Transaction_process
--------------------------------------------------------------------------------------------------------------
FUNCTION stopTask(l_emp RECORD LIKE emp01.*, l_job_link INTEGER, l_work_code CHAR(4), l_dt DATETIME YEAR TO SECOND)
		RETURNS BOOLEAN
	DEFINE l_trim1      RECORD LIKE trim1.*
	DEFINE l_clock_time LIKE trim1.swipe_time
	DEFINE l_trim2_key  INTEGER
&ifdef NOUPD
 DEBUG(0,"stopTask: NOUPD defined - not updating database!")
 RETURN TRUE
&endif

	LET l_clock_time = CURRENT
	DEBUG(2, SFMT("stopTask: %1:%2:%3:%4", l_emp.branch_code, l_emp.short_code, l_job_link, l_work_code))
-- Basic sanity checks
	IF l_emp.short_code IS NULL THEN
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

	SELECT * INTO l_trim1.* FROM trim1
			WHERE trim1.work_code = l_work_code AND trim1.job_link = l_job_link AND trim1.employee_code = l_emp.short_code
					AND trim1.branch_code = l_emp.branch_code
	IF STATUS = NOTFOUND THEN
		CALL dbLib_error("Task not started!")
		RETURN FALSE
	END IF

	IF l_trim1.command_code = "K" THEN
		CALL dbLib_error("Task already completed!")
		RETURN FALSE
	END IF

	IF NOT l_trim1.command_code MATCHES "[SG]" THEN
		CALL dbLib_error("Task not set to started!")
		RETURN FALSE
	END IF

--	LET l_trim2_key = transaction_process_stop(l_emp.pay_method, l_clock_time, "E", l_trim1.*)
	IF l_trim2_key = 0 THEN
		CALL dbLib_error("Stop process failed!")
		RETURN FALSE
	END IF

	RETURN TRUE
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- NOTE: Now not being used becuse we are using the  trimUpdateTask program instead.
FUNCTION completeTask(
		l_branch LIKE bra01.branch_code, l_emp_code LIKE emp01.short_code, l_job_link INTEGER, l_work_code CHAR(4))
		RETURNS BOOLEAN
	DEFINE x            SMALLINT
	DEFINE l_no_running SMALLINT
	DEFINE l_trim1      RECORD LIKE trim1.*
	DEFINE l_clock_time LIKE trim1.swipe_time
	DEFINE l_args       STRING
	DEFINE l_ret        INT
	DEFINE l_command    CHAR(1)
&ifdef NOUPD
 DEBUG(0,"completeTask: NOUPD defined - not updating database!")
  CALL dbLib_error( "NOUPD defined - not updating database!" )
 RETURN FALSE
&endif

	LET l_clock_time = CURRENT
	DEBUG(2, SFMT("completeTask: %1:%2:%3:%4", l_branch, l_emp_code, l_job_link, l_work_code))
	SELECT COUNT(*) INTO x FROM trim1
			WHERE trim1.work_code = l_work_code AND trim1.job_link = l_job_link AND trim1.employee_code = l_emp_code
					AND trim1.branch_code = l_branch
	IF x = 0 THEN
		CALL dbLib_error("Task not started!")
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

	SELECT * INTO l_trim1.* FROM trim1
			WHERE trim1.work_code = l_work_code AND trim1.job_link = l_job_link AND trim1.employee_code = l_emp_code
					AND trim1.branch_code = l_branch
	IF STATUS = NOTFOUND THEN
		CALL dbLib_error("Task not started!")
		RETURN FALSE
	END IF

-- check no one else has started work on this work_code
	SELECT COUNT(*) INTO l_no_running FROM trim1 WHERE trim1.work_code = l_work_code AND trim1.job_link = l_job_link
	IF l_no_running > 1 THEN
		CALL dbLib_error("Can't complete because tasks still acvite.")
		RETURN FALSE
	END IF

	LET l_command = "K"
	LET l_args    = SFMT("%1 %2 %3 %4 %5", l_branch, l_emp_code, l_job_link, l_work_code, l_command)
	LET l_ret     = runProg("trimUpdateTask", l_args)
	IF l_ret != 0 THEN
		CALL dbLib_error("Failed to set task complete!")
		RETURN FALSE
	END IF

	RETURN TRUE
END FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION checkTaskHeld(l_joblink INT, l_work_code LIKE trim1.work_code, l_complete BOOLEAN) RETURNS(BOOLEAN, STRING)
	DEFINE l_mess      STRING
	DEFINE l_held      BOOLEAN
	DEFINE l_who_by    STRING
	DEFINE l_list_link INTEGER
	-- get the list_link
	SELECT internal_no INTO l_list_link FROM lists WHERE work_code = l_work_code
	# Now check the task isn't held (and incidentally show any alerts)
{	IF l_complete THEN
		CALL task_alert_c(l_joblink, l_list_link) RETURNING l_held, l_mess, l_who_by
	ELSE
		CALL task_alert_s(l_joblink, l_list_link) RETURNING l_held, l_mess, l_who_by
	END IF}
	IF l_held THEN # Held From Starting
		LET l_mess = "Held By: ", l_who_by CLIPPED, "\n'", l_mess CLIPPED, "'"
	END IF
	RETURN l_held, l_mess.trim()
END FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION clearHold(l_joblink INT, l_work_code LIKE trim1.work_code, l_emp LIKE emp01.short_code)
	DEFINE l_list_link INTEGER
	-- get the list_link
	SELECT internal_no INTO l_list_link FROM lists WHERE work_code = l_work_code
	# write back last viewer to task_hold
	UPDATE task_hold SET last_seen_by = l_emp
			WHERE job_link = l_joblink AND list_link = l_list_link AND block = "N" AND cleared_dt IS NULL

	# If auto clear is set, don't pester the next person:
	UPDATE task_hold SET cleared_dt = CURRENT YEAR TO MINUTE, cleared_by = "^" || l_emp
			WHERE job_link = l_joblink AND list_link = l_list_link AND cleared_dt IS NULL AND block = "N" AND auto_clear = "Y"
END FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION create_lista_trim2(l_job_link INTEGER, l_list_link INTEGER, l_work_code LIKE lists.work_code)
	DEFINE
		l_lista      RECORD LIKE lista.*,
		l_lista_trim RECORD LIKE lista_trim.*,
		l_dt1        DATETIME YEAR TO SECOND,
		l_dt2        DATETIME YEAR TO SECOND,
		l_sdt        DATETIME YEAR TO MINUTE,
		l_edt        DATETIME YEAR TO MINUTE

	SELECT * INTO l_lista_trim.* FROM lista_trim
			WHERE lista_trim.job_link = l_job_link AND lista_trim.list_link = l_list_link AND lista_trim.entry_no = 0
	IF STATUS = 0 THEN
		IF l_lista_trim.recorded_time IS NULL THEN
			LET l_lista_trim.recorded_time = 0
		END IF
		IF l_lista_trim.claimed_time IS NULL THEN
			LET l_lista_trim.claimed_time = 0
		END IF
		RETURN l_lista_trim.*
	END IF

	SELECT * INTO l_lista.* FROM lista
			WHERE lista.job_link = l_job_link AND lista.list_link = l_list_link AND lista.entry_no = 0

	SELECT MAX(end_datetime) INTO l_dt1 FROM trim2
			WHERE trim2.job_link = l_job_link AND trim2.work_code = l_work_code AND trim2.stop_command = "K"

	SELECT MAX(end_datetime) INTO l_dt2 FROM trim2b
			WHERE trim2b.job_link = l_job_link AND trim2b.work_code = l_work_code AND trim2b.stop_command = "K"
	IF l_dt1 > l_dt2 THEN
		LET l_edt = l_dt1
	ELSE
		LET l_edt = l_dt2
	END IF

	SELECT MAX(start_datetime) INTO l_dt1 FROM trim2
			WHERE trim2.job_link = l_job_link AND trim2.work_code = l_work_code AND trim2.stop_command = "K"

	SELECT MAX(start_datetime) INTO l_dt2 FROM trim2b
			WHERE trim2b.job_link = l_job_link AND trim2b.work_code = l_work_code AND trim2b.stop_command = "K"
	IF l_dt1 > l_dt2 THEN
		LET l_sdt = l_dt1
	ELSE
		LET l_sdt = l_dt2
	END IF

	LET l_lista_trim.job_link      = l_job_link
	LET l_lista_trim.list_link     = l_list_link
	LET l_lista_trim.entry_no      = 0
	LET l_lista_trim.task_end      = l_edt
	LET l_lista_trim.task_start    = l_sdt
	LET l_lista_trim.recorded_time = l_lista.actual_hours
	LET l_lista_trim.claimed_time  = 0
	IF l_lista_trim.recorded_time IS NULL THEN
		LET l_lista_trim.recorded_time = 0
	END IF
	IF l_lista_trim.claimed_time IS NULL THEN
		LET l_lista_trim.claimed_time = 0
	END IF

	DELETE FROM lista_trim
			WHERE lista_trim.job_link = l_job_link AND lista_trim.list_link = l_list_link AND lista_trim.entry_no = 0

	INSERT INTO lista_trim VALUES(l_lista_trim.*)

	RETURN l_lista_trim.*
END FUNCTION # create_lista_trim()
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
	DEFINE l_q1 STRING
	DEBUG(2, SFMT("getTaskData: Br:%1 E:%2 R:%3 A:%4 D:%5 C:%6", l_branch, l_emp, l_rows, l_age, l_delivery, l_collection))
	LET l_q1 = taskCursor(l_rows: l_rows, l_age: l_age, l_branch: l_branch)
--	LET l_q1 = "SELECT 'jn', job_link FROM next_job WHERE employee = '",l_emp,"' AND branch = '",l_branch,"' ORDER BY job_link"
	DEBUG(2, l_q1)
	PREPARE statement1 FROM l_q1
	DECLARE sel_jobs SCROLL CURSOR FOR statement1
	RETURN getTasks(l_emp: l_emp, l_collection: l_collection, l_delivery: l_delivery)
END FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION getTasks(l_emp CHAR(4), l_collection INT, l_delivery INT) RETURNS DYNAMIC ARRAY OF t_listData1
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
	DEFINE l_dump      TEXT
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

	IF m_debug > 3 THEN
		--DEBUG: dump task list to a JSON file for debug only.
		LOCATE l_dump IN FILE "data.json"
		LET l_dump = util.json.stringify(l_arr)
	END IF
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
	DEFINE l_context STRING
	DEFINE l_stat    SMALLINT
	DEFINE l_source  STRING

		CALL dbLib_error("Cloud Store not enabled.")
		RETURN FALSE

END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Get a file from cloud storage
FUNCTION getFileForJob(l_job_link LIKE job01.job_link, l_path STRING, l_file STRING) RETURNS BOOLEAN
	DEFINE l_context STRING
	DEFINE l_stat    SMALLINT
	DEFINE l_target  STRING

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
	DEFINE x, y, z, i SMALLINT
	DEFINE l_context  STRING
	DEFINE l_stat     SMALLINT
	DEFINE l_skip     BOOLEAN
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

			IF os.path.isDirectory(l_path) THEN
				--DISPLAY "Dir:",path
				CONTINUE WHILE
			ELSE
				--DISPLAY "Fil:",path
			END IF

			LET l_ext = os.path.extension(l_path).toLowerCase()
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

			IF os.path.isDirectory(l_path) THEN
				--DISPLAY "Dir:",path
				CONTINUE WHILE
			ELSE
				--DISPLAY "Fil:",path
			END IF

			LET l_ext = os.path.extension(l_path).toLowerCase()
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
	DEFINE l_expected_date DATE
	DEFINE l_parts         RECORD LIKE parts.*
	DEFINE l_list_title    LIKE lists.list_title
	DEFINE x               SMALLINT = 0
	DEFINE l_status        STRING

	DECLARE c_get_parts_enq CURSOR FOR
			SELECT parts.*, list_title FROM parts, lists
					WHERE job_link = l_job_link AND entry_no <> 0 AND internal_no = list_link AND list_type IN ("P", "S")
					ORDER BY list_link, entry_no ASC

	FOREACH c_get_parts_enq INTO l_parts.*, l_list_title
		IF l_parts.p_status = "N" THEN
			CONTINUE FOREACH
		END IF
		LET x              = x + 1
		LET l_arr[x].line1 = l_parts.description
		CASE l_parts.p_status
			WHEN "N"
				LET l_status = "Not Required"
			WHEN "O"
				LET l_status = "Ordered"
			WHEN "D"
				LET l_status = "Delivered"
			WHEN "P"
				LET l_status = "Partly Delivered"
			WHEN "B"
				LET l_status = "Back Ordered"
			WHEN "M"
				LET l_status = "Memo"
			WHEN "R"
				LET l_status = "Returned"
			WHEN "C"
				LET l_status = "Credited"
			WHEN "S"
				LET l_status = "Sent To Stock"
			OTHERWISE
				IF l_parts.p_status IS NULL THEN
					LET l_parts.p_status = " " -- avoid null check errors.
					LET l_status         = "Not Ordered"
				ELSE
					LET l_status = SFMT("Unknown Status '%1'", l_parts.p_status)
				END IF
		END CASE
		LET l_expected_date = NULL
		CASE l_list_title
			WHEN "NEW PARTS"
				IF l_parts.stock_no IS NOT NULL THEN
					LET l_arr[x].line1    = l_arr[x].line1.append(SFMT(" ( %1 )", l_parts.stock_no CLIPPED))
				END IF
				LET l_arr[x].line_img = "parts"
				IF l_parts.no_delivered > 0 AND l_parts.p_status = "D" THEN
					LET l_arr[x].line_img = "parts_del"
				END IF
				IF l_parts.order_no IS NOT NULL AND l_parts.back_order = "N" THEN
					SELECT required_date INTO l_expected_date FROM ord01
							WHERE ord01.order_no = l_parts.order_no AND ord01.job_link = l_parts.job_link
				END IF
				IF l_parts.order_date IS NOT NULL AND l_parts.back_order = "Y" THEN
					LET l_expected_date = DATE(l_parts.back_order_dt)
				END IF
				IF l_expected_date IS NOT NULL AND l_parts.p_status != "D" AND l_parts.p_status != "N" THEN
					LET l_status = SFMT(" Expected: <b>%1</b>", l_expected_date)
				END IF
				IF l_parts.bin_loc IS NOT NULL AND l_parts.p_status = "D" THEN
					LET l_status = SFMT(" Bin: <b>%1</b>", l_parts.bin_loc CLIPPED)
				END IF

				LET l_arr[x].line2 = SFMT("Qty: <b>%1</b> %2", l_parts.quantity, l_status)
			WHEN "SPECIALIST SERVICES"
				LET l_arr[x].line_img = "services"
				LET l_arr[x].line2    = l_status
			OTHERWISE
				LET l_arr[x].line_img = "help"
		END CASE
		DEBUG(3, SFMT("getPartsForJob: %1 %2 PS: %3 EX: %4 BO: %5 S: %6", l_list_title CLIPPED, l_parts.description, l_parts.p_status, l_expected_date, l_parts.back_order, l_status))

	END FOREACH
	DEBUG(2, SFMT("getPartsForJob: JL: %1 Rows: %2", l_job_link, l_arr.getLength()))

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
	DEFINE x             SMALLINT
	DEFINE l_lists_rec   RECORD LIKE lists.*
	DEFINE l_lista_rec   RECORD LIKE lista.*
	DEFINE l_cnt         SMALLINT
	DEFINE l_overrun_b   BOOLEAN
	DEFINE l_running     BOOLEAN
	DEFINE l_started     BOOLEAN
	DEFINE l_isAllocated BOOLEAN
	DEFINE l_st          STRING
	DEFINE l_overrun     DECIMAL(9, 2)
	DEFINE l_worked_time DECIMAL(9, 2)
	DEFINE l_interval    INTERVAL DAY(3) TO SECOND

	LET l_overrun = 0
	IF l_overrun IS NULL OR l_overrun < 1 THEN
		DEBUG(0, "TRIM_OVERRUN appears to be broken")
		LET l_overrun = 1.05
	END IF

	DECLARE tfj_cur CURSOR FOR
			SELECT * FROM lista, lists
					WHERE lista.job_link = l_job_link AND lista.entry_no = 0 -- ORDER BY estimated_date, list_link
							AND lists.internal_no = lista.list_link
					ORDER BY report_no ASC
	--DECLARE tfj_ls_cur CURSOR FOR SELECT * FROM lists WHERE lists.internal_no = l_lista_rec.list_link
	FOREACH tfj_cur INTO l_lista_rec.*, l_lists_rec.*
		IF l_lists_rec.job_sheet_title IS NULL THEN
			CONTINUE FOREACH
		END IF
		--OPEN tfj_ls_cur
		--FETCH tfj_ls_cur INTO l_lists_rec.*
		--CLOSE tfj_ls_cur

-- Look for a trim1 record to see if it's in-progress
		LET l_running     = FALSE
		LET l_started     = FALSE
		LET l_isAllocated = FALSE
		LET l_worked_time = 0
		SELECT COUNT(*), SUM(CURRENT - swipe_time) INTO l_cnt, l_interval FROM trim1
				WHERE job_link = l_job_link AND work_code = l_lists_rec.work_code AND trim1.interrupt_flag IS NULL
						AND trim1.interrupt_time IS NULL
		IF l_cnt > 0 THEN
			LET l_running = TRUE
		END IF
		IF l_running THEN
			LET l_started     = TRUE
	--		LET l_worked_time = conv_time_to_dec_(l_interval)
		ELSE
			IF l_lista_rec.actual_hours IS NOT NULL AND l_lista_rec.actual_hours > 0 THEN
				LET l_started = TRUE
			END IF
		END IF

		LET l_worked_time = l_worked_time + l_lista_rec.actual_hours
		LET l_overrun_b   = l_worked_time * l_overrun > l_lista_rec.workshop_hours

		SELECT COUNT(*) INTO l_cnt FROM next_job
				WHERE next_job.job_link = l_job_link AND next_job.task = l_lista_rec.list_link AND next_job.taken IS NULL
		IF l_cnt > 0 THEN
			LET l_isAllocated = TRUE
		END IF

		LET x = x + 1
		CALL getTaskStatus(l_lista_rec.p_status, l_running, l_started, l_overrun_b, l_isAllocated)
				RETURNING l_st, l_arr[x].line_img

		LET l_arr[x].line1 = l_lists_rec.job_sheet_title
		LET l_arr[x].line2 =
				SFMT("WorkShop Hours: %1 Actual Hours: %2", l_lista_rec.workshop_hours, l_lista_rec.actual_hours)
{
		LET l_arr[x].line_img = "grey"
		IF l_lista_rec.actual_hours > 0 THEN
			LET l_arr[x].line_img = "grey"
		END IF
		IF l_lista_rec.p_status > 63 THEN
			LET l_arr[x].line_img = "blue"
			IF l_t1 > 0 THEN -- we have a trim1 record for the task it must be progress?
				LET l_arr[x].line_img = "amber"
			END IF
		END IF
		IF l_lista_rec.p_status > 127 THEN
			LET l_arr[x].line_img = "green"
		END IF
		IF l_lista_rec.workshop_hours > 0 AND l_lista_rec.actual_hours > 0 THEN
			IF l_lista_rec.workshop_hours - l_lista_rec.actual_hours < 0 THEN
				LET l_light = FALSE
			END IF
		END IF
		IF l_light THEN
			LET l_arr[x].line_img = l_arr[x].line_img.append("_light")
		ELSE
			LET l_arr[x].line_img = l_arr[x].line_img.append("_dark")
		END IF
}
		DEBUG(3, SFMT("getTasksForJob JL: %1, %2 Titl: %3 img: %4 WH: %5 AH: %6 OV: %7 ST: %8", l_job_link, x, l_lists_rec.job_sheet_title, l_arr[x].line_img, l_lista_rec.workshop_hours, l_lista_rec.actual_hours, l_overrun_b, l_st))
	END FOREACH

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
FUNCTION isClockedOn(l_empCode LIKE trim1.employee_code, l_branch LIKE trim1.branch_code)
		RETURNS(BOOLEAN, LIKE trim1.swipe_time)
	DEFINE l_count SMALLINT
	DEFINE l_dt    LIKE trim1.swipe_time
	DEBUG(2, SFMT("isClockedOn: %1 %2 ...", l_empCode, l_branch))
	SELECT COUNT(*) INTO l_count FROM trim1
			WHERE trim1.employee_code = l_empCode AND trim1.branch_code = l_branch AND trim1.work_code = "__ON"
					AND trim1.command_code = "X"
	IF l_count = 1 THEN
		SELECT swipe_time INTO l_dt FROM trim1
				WHERE trim1.employee_code = l_empCode AND trim1.branch_code = l_branch AND trim1.work_code = "__ON"
						AND trim1.command_code = "X"
	END IF
	DEBUG(2, SFMT("isClockedOn: %1 %2 %3", l_empCode, l_branch, l_count))
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
	DEFINE c               base.channel
-- check release dir exists
	LET l_dir = os.path.join(m_db_moblib.cfg.baseDir, m_db_moblib.sysName)
	IF NOT os.path.exists(l_dir) THEN
		CALL stdLib.error(SFMT("Folder not found '%1'", l_dir), TRUE)
		RETURN -1
	END IF

-- check generorun.sh exists
	IF NOT os.path.exists("generorun.sh") THEN
		CALL stdLib.error("generorun.sh not found!", TRUE)
		RETURN -1
	END IF

-- check program exists
	IF NOT os.path.exists(os.path.join(l_dir, l_prog || ".42r")) THEN
		CALL stdLib.error(SFMT("Program '%1' not found", l_prog), TRUE)
		RETURN -1
	END IF

-- Genero
	LET l_genero = SFMT("/opt/fourjs/fgl%1", m_db_moblib.eclipseGenVer)
	IF NOT os.path.exists(l_genero) THEN
		CALL stdLib.error(SFMT("Failed to find '%1'", l_genero), TRUE)
		RETURN -1
	END IF

	DEBUG(3, SFMT("runProg: Now in %1", l_dir))
-- set env and run program
	LET l_progDir = os.path.join(m_db_moblib.cfg.baseDir, m_db_moblib.sysName)

	CALL fgl_setEnv("DBNAME", m_db_moblib.dbName)
	CALL fgl_setEnv("LOGNAME", m_db_moblib.user_id)
	CALL fgl_setEnv("CONO", m_db_moblib.reg.cono)
	CALL fgl_setEnv("BASEDIR", m_db_moblib.cfg.baseDir)
	CALL fgl_setEnv("SYSNAME", m_db_moblib.sysName)
	CALL fgl_setEnv("PROGDIR", l_progDir)
	CALL fgl_setEnv("DATADIR", m_db_moblib.cfg.fileStorage)
	CALL fgl_setEnv("TRIMDOCS", m_db_moblib.cfg.docPath)
	CALL fgl_setEnv("FGLPROFILE", NULL)

	LET l_cmd =
			SFMT("./generorun.sh %1 %2 %3.run %4.42r %5",
					m_db_moblib.eclipseGenVer, l_dir, stdLib.m_debugFile, l_prog, l_args)
	DEBUG(3, SFMT("runProg: in %1", os.path.pwd()))
	DEBUG(3, SFMT("runProg: run: %1", l_cmd))
	LET c = base.Channel.create()
	CALL C.openPipe(l_cmd, "r")
	WHILE NOT c.isEof()
		LET l_result = l_result.append(c.readLine())
	END WHILE
	CALL C.close()
	IF l_result != "Okay" THEN
		CALL stdLib.error(SFMT("Run: %1\nFailed: %2 %3", l_cmd, l_ret, l_result), TRUE)
	END IF
	DEBUG(3, SFMT("runProg: Returned %1 %2", l_ret, l_result))

	RETURN l_ret
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Error handler
FUNCTION dbLib_error(l_msg STRING)
	LET m_lastError = l_msg
	CALL stdLib.error(l_msg, m_doPopups)
END FUNCTION
