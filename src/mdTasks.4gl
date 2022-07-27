IMPORT util
IMPORT os

IMPORT FGL mobLib
IMPORT FGL stdLib
IMPORT FGL dbLib
IMPORT FGL mdUsers

&include "schema.inc"

&define DEBUG( l_lev, l_msg ) IF this.mobLib.cfg.debug THEN CALL stdLib.debugOut( l_lev, __FILE__, __LINE__, l_msg ) END IF

CONSTANT C_TRIMTASK_NOTSTARTED = "trimtask_notstarted"
CONSTANT C_TRIMTASK_STARTED    = "trimtask_started"
CONSTANT C_TRIMTASK_STOPPED    = "trimtask_stopped"
CONSTANT C_TRIMTASK_COMPLETE   = "trimtask_complete"
CONSTANT C_TRIMTASK_NODOC      = "trimtask_nodoc"
CONSTANT C_TRIMTASK_NOTALLOWED = "trimtask_notallowed"
CONSTANT C_TRIMTASK_PDF        = "trimtask_pdf"
CONSTANT C_TRIMTASK_DOC        = "trimtask_doc"
CONSTANT C_TRIMTASK_IMG        = "trimtask_img"
CONSTANT C_TRIMTASK_UNK        = "trimtask_unk"

CONSTANT C_TRIMTASK_STATE_NOTSTARTED = 0
CONSTANT C_TRIMTASK_STATE_STARTED    = 1
CONSTANT C_TRIMTASK_STATE_STOPPED    = 2
CONSTANT C_TRIMTASK_STATE_COMPLETED  = 3

TYPE t_task RECORD -- Details for a task.
	id      INTEGER,
	my_task BOOLEAN,
	line1   STRING,
	line2   STRING,
	state   SMALLINT, -- 0=stopped / 1=started / 2=ended / 3=complete
	trim    SMALLINT, -- 1 trim1 / 2 trim2 / 3 next_job
	allowed BOOLEAN
END RECORD

TYPE t_taskScrArr RECORD -- Screen array record for tasks
	line1 STRING,
	line2 STRING,
	img   STRING,
	id    STRING
END RECORD

PUBLIC TYPE mdTasks RECORD -- The Task Object Structure
	rec         t_task,
	cur_idx     SMALLINT,
	branch      CHAR(2),
	getOtherAge CHAR(5),                -- refetch 'other' tasks if list is other than this
	getEmpAge   CHAR(5),                -- refetch 'user' tasks if list is other than this
	gotUser     DATETIME DAY TO MINUTE, -- Timestamp for the last read of data for user tasks
	gotOther    DATETIME DAY TO MINUTE, -- Timestamp for the last read of data for other tasks
	delivery    INTEGER,
	collection  INTEGER,
	job_age     SMALLINT,
	job_rows    INTEGER,
	list        DYNAMIC ARRAY OF t_task,
	taskRec     dbLib.t_listData1,
	task_count  SMALLINT,
	mobLib      mobLib,
	mdUser      mdUsers
END RECORD

DEFINE m_TasksArr DYNAMIC ARRAY OF dbLib.t_listData1

FUNCTION tt_dummy()
	WHENEVER ERROR CALL app_error
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Set the structure.
FUNCTION (this mdTasks) init(l_user mdUsers INOUT, l_mobLib mobLib INOUT)
	LET this.mdUser      = l_user
	LET this.mobLib      = l_mobLib
	LET this.branch      = this.mdUser.emp_rec.branch_code
	LET this.delivery    = -1
	LET this.collection  = -1
	LET this.getEmpAge   = this.mobLib.cfg.refreshAge
	LET this.getOtherAge = this.mobLib.cfg.refreshAge
	LET this.job_rows    = 5000
	LET this.job_age     = this.mobLib.cfg.jobAge
	CALL this.list.clear()
	DEBUG(1, SFMT("init - user: %1 branch: %2 delivery: %3 collection: %4", l_user.emp_rec.short_code, this.branch, this.delivery, this.collection))
	LET this.gotOther = NULL
	LET this.gotUser  = NULL
	CALL this.getTasks(TRUE)
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Update the 'list' array with current tasks for either specific user or 'other' tasks.
FUNCTION (this mdTasks) getTasks(l_forUser BOOLEAN) RETURNS()
	DEFINE l_age, l_chk INTERVAL HOUR TO MINUTE

	IF NOT l_forUser THEN
		LET l_age = CURRENT - this.gotOther
		LET l_chk = this.getOtherAge
	ELSE
		LET l_age = CURRENT - this.gotUser
		LET l_chk = this.getEmpAge
	END IF
	DEBUG(1, SFMT("getTasks: forUSer: %1 Age: %2  Check: %3 ", IIF(l_forUser, "True", "False"), NVL(l_age, "NULL"), l_chk))
-- only get new tasks if the current task list is older that the required age or we don't have a task list.
	IF l_age IS NULL OR l_age > l_chk OR this.list.getLength() = 0 THEN
		CALL this.loadArray(l_forUser)
		IF NOT l_forUser THEN
			LET this.gotOther = CURRENT
		ELSE
			LET this.gotUser = CURRENT
		END IF
	END IF
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Set the internal 'rec' to the ID of the passed in ID.
--
-- @param l_id ID of the task
FUNCTION (this mdTasks) setCurrentRec(l_id INTEGER) RETURNS BOOLEAN
	DEFINE x SMALLINT
	LET this.cur_idx = 0
	DEBUG(2, SFMT("setCurrentRec: %1", l_id))
	FOR x = 1 TO this.list.getLength()
		IF this.list[x].id = l_id THEN
			LET this.cur_idx = x
			LET this.rec.* = this.list[x].*
			LET this.taskRec.* = m_tasksArr[l_id].*
			EXIT FOR
		END IF
	END FOR
	IF this.cur_idx = 0 THEN
		RETURN FALSE
	END IF
	RETURN TRUE
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Show the information for the task bsaed on the ID passed or current task if NULL is past.
--
-- @param l_id ID of the task
FUNCTION (this mdTasks) info(l_id INTEGER) RETURNS()
	DEFINE l_opt     SMALLINT
	DEFINE l_makecur STRING

	DEBUG(2, SFMT("info: %1", l_id))
	IF l_id IS NULL OR l_id = 0 THEN
		CALL stdLib.error("No current task set", TRUE)
		RETURN
	END IF

	IF NOT this.setCurrentRec(l_id) THEN
		CALL stdLib.error(SFMT("cant find current '%1'", l_id), FALSE)
		RETURN
	END IF

	OPEN WINDOW taskinfo WITH FORM this.mobLib.openForm("mdTask_info")
	CALL this.dispTask(FALSE)

	WHILE TRUE
-- Setup the menu options
		CALL this.mobLib.buttons.clear()
		LET this.mobLib.buttons[1].text    = "Start Task"
		LET this.mobLib.buttons[1].enabled = (this.rec.state != 1)
		LET this.mobLib.buttons[1].img     = C_TRIMTASK_STARTED
		LET this.mobLib.buttons[2].text    = "Complete Task"
		LET this.mobLib.buttons[2].enabled = (this.rec.state = 1)
		LET this.mobLib.buttons[2].img     = C_TRIMTASK_COMPLETE
		LET this.mobLib.buttons[3].text    = "Stop Task"
		LET this.mobLib.buttons[3].enabled = (this.rec.state = 1)
		LET this.mobLib.buttons[3].img     = C_TRIMTASK_STOPPED
		LET this.mobLib.buttons[4].text    = "Take Image"
		LET this.mobLib.buttons[4].img     = "add_a_photo"
		LET this.mobLib.buttons[5].text    = "Job Enquiry"
		LET this.mobLib.buttons[5].img     = "build"
		LET this.mobLib.buttons[6].text    = "Show Job Card"
		LET this.mobLib.buttons[6].img     = "article"
		LET this.mobLib.buttons[7].text    = "Back"
		LET this.mobLib.buttons[7].img     = "back"
		LET int_flag                       = FALSE

		IF NOT this.rec.allowed THEN
			LET this.mobLib.buttons[1].enabled = FALSE
			LET this.mobLib.buttons[2].enabled = FALSE
			LET this.mobLib.buttons[3].enabled = FALSE
		END IF

		LET l_makecur = "_Make this the Current Task"
-- Do the menu
		LET l_opt = this.mobLib.doMenu("Task Options:", TRUE)
		CASE l_opt
			WHEN 1 -- Start
				IF this.start(this.rec.id) THEN
					EXIT WHILE
				END IF
			WHEN 2 -- Complete
				IF this.complete(this.rec.id) THEN
					EXIT WHILE
				END IF
			WHEN 3 -- Stop working on a task.
				IF this.stop(this.rec.id) THEN
					EXIT WHILE
				END IF
			WHEN 4
				CALL this.takeImage()
			WHEN 5 -- Job Enquiry
				CALL this.job_enquiry()
			WHEN 6 -- Job Card
				CALL this.jobCard()
			OTHERWISE
				EXIT WHILE
		END CASE
	END WHILE

	CLOSE WINDOW taskinfo
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Set the task of the passed in ID to the 'started' - this also becomes the 'current' task
--
-- @param l_id ID of the task
FUNCTION (this mdTasks) dispTask(l_jobOnly BOOLEAN) RETURNS()
	DEFINE l_pstat CHAR(1)
	DEFINE l_stat  CHAR(5)
	DISPLAY BY NAME this.taskRec.job_number
	DISPLAY this.taskRec.veh_reg TO veh_reg
	DISPLAY this.taskRec.veh_colour TO veh_clr
	DISPLAY this.taskRec.veh_make CLIPPED TO veh
	DISPLAY BY NAME this.taskRec.contact
	DISPLAY this.taskRec.sch_handover TO scheduled_handover
	LET l_stat = "JOB"
	IF NOT l_jobOnly THEN
		DISPLAY BY NAME this.taskRec.list_title -- Task
		DISPLAY BY NAME this.taskRec.state_desc
		LET l_pstat = "N"
-- NOTE: our testBit is 0 indexes, so bit 1 is postion 0
		IF util.Integer.testBit(this.taskRec.list_status, 0) THEN
			LET l_pstat = "T"
		END IF
		IF util.Integer.testBit(this.taskRec.list_status, 6) THEN
			LET l_pstat = "I"
		END IF
		IF util.Integer.testBit(this.taskRec.list_status, 7) THEN
			LET l_pstat = "K"
		END IF
		LET l_stat =
				SFMT("%1%2%3%4%5", this.rec.state, this.taskRec.trim_cmd, this.taskRec.trim_stop, this.taskRec.trim, l_pstat)
		DISPLAY l_stat TO state
		LET this.taskRec.time_remaining = dbLib.timeRemaining(this.taskRec.*)
		DISPLAY this.taskRec.time_remaining TO time_remaining
	END IF
	DEBUG(1, SFMT("dispTask: %1 %2: %3 %4", this.taskRec.job_number, this.taskRec.work_code, l_stat, this.taskRec.list_status))

END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Set the task of the passed in ID to the 'started' - this also becomes the 'current' task
--
-- @param l_id ID of the task
FUNCTION (this mdTasks) start(l_id STRING) RETURNS BOOLEAN
	DEFINE l_msg       STRING
	DEFINE l_held      BOOLEAN
	DEFINE l_reason    STRING
	DEFINE l_current   SMALLINT
	DEFINE l_allocated SMALLINT
	DEBUG(2, SFMT("start: ID: %1 ", l_id))
	IF NOT this.setCurrentRec(l_id) THEN
		RETURN FALSE
	END IF
	DEBUG(1, SFMT("start: ID: %1 JL: %2 WC: %3", l_id, this.taskRec.job_link, this.taskRec.work_code))

	IF NOT this.mdUser.checkEmployee("S", NULL, NULL) THEN
		DEBUG(3, "start: failed checkEmployee ")
		RETURN FALSE
	END IF

	CALL dbLib.activeTasks(this.mdUser.emp_rec.short_code) RETURNING l_current

	IF l_current > 0 THEN
		DEBUG(3, "start: Already have an active task")
		ERROR "You already have an active task"
		RETURN FALSE
	END IF

	LET l_msg = "Confirm Starting work on this task?"
	IF NOT stdLib.confirm(l_msg, TRUE, 0) THEN
		RETURN FALSE
	END IF

	CALL dbLib.checkTaskHeld(this.taskRec.job_link, this.taskRec.work_code, FALSE) RETURNING l_held, l_reason
	IF l_reason IS NOT NULL THEN
		CALL stdLib.popup("Task On Hold", l_reason, "information", this.mobLib.cfg.timeouts.long)
		IF l_held THEN
			RETURN FALSE
		ELSE
			CALL dbLib.clearHold(this.taskRec.job_link, this.taskRec.work_code, this.mdUser.emp_rec.short_code)
		END IF
	END IF

	LET m_TasksArr[l_id].started = CURRENT
	IF dbLib.startTask(
			this.mdUser.emp_rec.short_code, this.taskRec.job_link, this.taskRec.work_code) THEN
		MESSAGE "Task Started"
	ELSE
		ERROR "Task Failed to Start!"
		RETURN FALSE
	END IF
	CALL this.list.clear() --  force the re-read of the list.
	RETURN TRUE
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Set the task of the passed in ID to 'complete'
--
-- @param l_id ID of the task
FUNCTION (this mdTasks) complete(l_id STRING) RETURNS BOOLEAN
	DEFINE l_msg    STRING
	DEFINE l_held   BOOLEAN
	DEFINE l_reason STRING

	DEBUG(2, SFMT("complete: ID: %1 ", l_id))
	IF NOT this.setCurrentRec(l_id) THEN
		RETURN FALSE
	END IF

	LET l_msg = "Confirm Complete Task?"
	IF NOT stdLib.confirm(l_msg, TRUE, 0) THEN
		RETURN FALSE
	END IF

	CALL dbLib.checkTaskHeld(this.taskRec.job_link, this.taskRec.work_code, TRUE) RETURNING l_held, l_reason
	IF l_reason IS NOT NULL THEN
		CALL stdLib.popup("Task On Hold", l_reason, "information", this.mobLib.cfg.timeouts.long)
		IF l_held THEN
			RETURN FALSE
		ELSE
			CALL dbLib.clearHold(this.taskRec.job_link, this.taskRec.work_code, this.mdUser.emp_rec.short_code)
		END IF
	END IF

	DEBUG(1, SFMT("complete: ID: %1 JL: %2 WC: %3", l_id, this.taskRec.job_link, this.taskRec.work_code))
	IF NOT dbLib.completeTask(this.mdUser.emp_rec.short_code, this.taskRec.job_link, this.taskRec.work_code) THEN
		ERROR dbLib.m_lastError
		RETURN FALSE
	END IF

	CALL this.list.clear() --  force the re-read of the list.
	MESSAGE "Task Completed."
	RETURN TRUE

END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Set the task of the passed in ID to 'stopped'
--
-- @param l_id ID of the task
FUNCTION (this mdTasks) stop(l_id STRING) RETURNS BOOLEAN
	DEFINE l_msg STRING
	DEBUG(2, SFMT("stop: ID: %1 ", l_id))
	IF NOT this.setCurrentRec(l_id) THEN
		RETURN FALSE
	END IF

	LET l_msg = "Confirm you are Stopping work on this task?"
	IF NOT stdLib.confirm(l_msg, TRUE, 0) THEN
		RETURN FALSE
	END IF

	DEBUG(1, SFMT("stop: ID: %1 JL: %2 WC: %3", l_id, this.taskRec.job_link, this.taskRec.work_code))
	LET m_TasksArr[l_id].stopped = CURRENT
	IF dbLib.stopTask(this.mdUser.emp_rec.short_code, this.taskRec.job_link, this.taskRec.work_code) THEN
		LET this.rec.state                  = C_TRIMTASK_STATE_STOPPED
		LET this.list[this.cur_idx].state   = this.rec.state
		LET this.list[this.cur_idx].my_task = TRUE
		MESSAGE "Task Stopped"
	ELSE
		ERROR "Stop Task Failed!"
		RETURN FALSE
	END IF
	CALL this.list.clear() --  force the re-read of the list.
	RETURN TRUE
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Take an image and attach it to this task.
FUNCTION (this mdTasks) takeImage() RETURNS()
	DEFINE l_cli_uri, l_srv_fn STRING
	DEFINE l_file, l_dte       STRING
--	DEFINE l_data              BYTE
	DEFINE l_func STRING

	IF NOT this.mobLib.feMobile THEN
		CALL stdLib.popup("Camera", "Feature only supported on Mobile devices", "exclamation", 0)
		RETURN
	END IF

	LET l_func   = "takePhoto"
	LET int_flag = FALSE
	MENU "Image" ATTRIBUTES(STYLE = "dialog", COMMENT = "Take or Choose Photo?", IMAGE = "question")
		COMMAND "Take"
		COMMAND "Choose"
			LET l_func = "choosePhoto"
		ON ACTION cancel ATTRIBUTE(IMAGE = "")
			LET int_flag = TRUE
	END MENU
	IF int_flag THEN
		LET int_flag = FALSE
		RETURN
	END IF
	DEBUG(1, SFMT("takeImage:  %1", l_func))
	TRY
		CALL ui.Interface.frontCall("mobile", l_func, [], [l_cli_uri])
	CATCH
		CALL stdLib.error(SFMT("%1:%2", STATUS, ERR_GET(STATUS)), TRUE)
		RETURN
	END TRY
	IF l_cli_uri IS NULL THEN
		DEBUG(1, "takeImage: cancelled.")
		CALL stdLib.popup("Image", "Cancelled", "info", 0)
		RETURN
	END IF

	DEBUG(2, SFMT("takeImage: URI: %1", l_cli_uri))
	CALL stdLib.notify("Getting image from device ...")
	LET l_dte    = util.Datetime.format(CURRENT, "%Y%m%d_%H%M%S")
	LET l_file   = "IMG_" || this.taskRec.job_link || "_" || this.taskRec.work_code || "_" || l_dte || ".jpg"
	LET l_srv_fn = os.path.join(this.mobLib.cfg.imgPath, l_file)
	--CALL stdLib.popup("Image", SFMT("%1\nSaved: %2", l_cli_uri, l_srv_fn), "info", 0)
	DEBUG(2, SFMT("takeImage: get %1 to %2", l_cli_uri, l_srv_fn))
	TRY
		CALL fgl_getfile(l_cli_uri, l_srv_fn)
		DEBUG(2, "getFile Okay")
--		LOCATE l_data IN FILE l_srv_fn -- what was this for ?
	CATCH
		LET l_file = SFMT("File Transfer Problem!\n%1 %2", STATUS, ERR_GET(STATUS))
		DEBUG(0, l_file)
		CALL stdLib.notify(NULL)
		CALL stdLib.popup("Image", l_file, "info", 0)
		RETURN
	END TRY
	IF STATUS != 0 THEN
		LET l_file = SFMT("File Transfer Problem!\n%1 %2", STATUS, ERR_GET(STATUS))
		DEBUG(0, l_file)
		CALL stdLib.notify(NULL)
		CALL stdLib.popup("Image", l_file, "info", 0)
	END IF
	CALL stdLib.notify("Sending image to cloud ...")
	SLEEP 1
	IF dbLib.putFileForJob(this.taskRec.job_link, this.mobLib.cfg.imgPath, l_file) THEN
		MESSAGE "Image saved."
	END IF
	CALL stdLib.notify(NULL)

END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Equire on the job details relating to this task.
FUNCTION (this mdTasks) job_enquiry() RETURNS()
	DEFINE l_opt SMALLINT
	DEFINE l_f   ui.Form
	DEFINE l_arr DYNAMIC ARRAY OF RECORD
		line1    STRING,
		line2    STRING,
		line_img STRING
	END RECORD

	OPEN WINDOW taskenq WITH FORM this.mobLib.openForm("mdJob_info")
	LET l_f = ui.Window.getCurrent().getForm()
	CALL l_f.setElementHidden("lab4", TRUE)
	CALL l_f.setFieldHidden("formonly.list_title", TRUE)
	CALL l_f.setElementHidden("lab5", TRUE)
	CALL l_f.setFieldHidden("formonly.l_state", TRUE)
	CALL l_f.setElementHidden("lab6", TRUE)
	CALL l_f.setFieldHidden("formonly.time_remaining", TRUE)
	CALL l_f.setElementHidden("tasks", FALSE)

	CALL this.dispTask(TRUE)

	LET l_arr = dbLib.getTasksForJob(this.taskRec.job_link)

-- define the menu actions
	CALL this.mobLib.buttons.clear()
	LET this.mobLib.buttons[1].text = "Parts/Sublet"
	LET this.mobLib.buttons[1].img  = "miscellaneous_services"
	LET this.mobLib.buttons[2].text = "View Docs/Images"
	LET this.mobLib.buttons[2].img  = "camera_roll"
	LET this.mobLib.buttons[3].text = "Back"
	LET this.mobLib.buttons[3].img  = "back"

-- setup menu buttons
	LET l_opt    = this.mobLib.doMenu("Job Enquire:", FALSE)
	LET int_flag = FALSE
	DEBUG(1, SFMT("job_enquiry: Display Array, timeout is %1 rows: %2", this.mobLib.cfg.timeouts.medium, l_arr.getLength()))
	DISPLAY ARRAY l_arr TO arr.*
		BEFORE DISPLAY
			CALL this.mobLib.menuSetActive(DIALOG)
		ON IDLE this.mobLib.cfg.timeouts.medium
			LET int_flag = TRUE
			EXIT DISPLAY
		ON ACTION enterbackground
			LET int_flag = TRUE
			EXIT DISPLAY
		ON ACTION opt1
			CALL this.parts()
		ON ACTION opt2
			CALL this.viewDocs()
		ON ACTION opt3
			EXIT DISPLAY
	END DISPLAY

	CLOSE WINDOW taskenq

END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- View the job card
FUNCTION (this mdTasks) jobCard() RETURNS()
	DEFINE l_tmp STRING
	DEFINE l_ret SMALLINT

	IF this.mdUser.emp_rec.user_id IS NULL THEN
		CALL stdLib.error("No user_id for this employee!", TRUE)
		RETURN
	END IF
	DEBUG(1, SFMT("jobCard: for %1 %2", this.mdUser.branch, this.taskRec.job_link))
	CALL stdLib.notify("Producing Job Sheet.\nplease wait ...")
	LET l_ret = dbLib.productJobSheet(this.mdUser.branch, this.mdUser.emp_rec.user_id, this.taskRec.job_link)
	IF l_ret = 0 THEN
		LET l_tmp = this.mobLib.showFile(this.mobLib.cfg.docPath, SFMT("JS_%1.pdf", this.taskRec.job_link), TRUE)
	ELSE
		DEBUG(1, SFMT("jobCard: Failed %1", l_ret))
	END IF
	CALL stdLib.notify(NULL)
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- View job info
FUNCTION (this mdTasks) fullInfo() RETURNS()
	CALL this.mobLib.futureFeature("More Job Info")
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- View Parts / Sublet
FUNCTION (this mdTasks) parts() RETURNS()
	DEFINE l_arr DYNAMIC ARRAY OF RECORD
		line1    STRING,
		line2    STRING,
		line_img STRING
	END RECORD

	OPEN WINDOW taskparts WITH FORM this.mobLib.openForm("mdJob_parts")
	CALL this.dispTask(TRUE)
	LET l_arr = dbLib.getPartsForJob(this.taskRec.job_link)
	DEBUG(1, SFMT("parts: Display Array, timeout is %1 rows: %2", this.mobLib.cfg.timeouts.medium, l_arr.getLength()))
	DISPLAY ARRAY l_arr TO arr.*
		ON ACTION back
			EXIT DISPLAY
		ON IDLE this.mobLib.cfg.timeouts.medium
			LET int_flag = TRUE
			EXIT DISPLAY
		ON ACTION enterbackground
			LET int_flag = TRUE
			EXIT DISPLAY
	END DISPLAY
	CLOSE WINDOW taskparts

END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- View documents relating to this task.
FUNCTION (this mdTasks) viewDocs() RETURNS()
	DEFINE
		l_arr DYNAMIC ARRAY OF RECORD
			line1       STRING,
			line2       STRING,
			line_img    STRING,
			cf_or_local CHAR(1)
		END RECORD,
		l_path STRING,
		x      SMALLINT

	OPEN WINDOW taskdocs WITH FORM this.mobLib.openForm("mdJob_docs")

	CALL this.dispTask(TRUE)
	LET l_arr = dbLib.getDocsForJob(this.taskRec.job_link, this.mobLib.cfg.docPath, this.mobLib.cfg.imgPath)

	IF l_arr.getLength() = 0 THEN
		LET l_arr[1].line1    = "No Documents Found"
		LET l_arr[1].line_img = C_TRIMTASK_NODOC
	ELSE
		FOR x = 1 TO l_arr.getLength()
			LET l_path = this.mobLib.cfg.docPath
			CASE l_arr[x].line_img
				WHEN "img"
					LET l_arr[x].line_img = C_TRIMTASK_IMG
					LET l_path            = this.mobLib.cfg.imgPath
				WHEN "pdf"
					LET l_arr[x].line_img = C_TRIMTASK_PDF
				WHEN "doc"
					LET l_arr[x].line_img = C_TRIMTASK_DOC
				WHEN "unk"
					LET l_arr[x].line_img = C_TRIMTASK_UNK
			END CASE
			IF l_arr[x].cf_or_local = "C" AND os.path.exists(os.path.join(l_path, l_arr[x].line1)) THEN
				LET l_arr[x].cf_or_local = "L"
			END IF
			IF l_arr[x].cf_or_local = "C" THEN
				LET l_arr[x].line_img = l_arr[x].line_img || "cloud"
			ELSE
				LET l_arr[x].line_img = l_arr[x].line_img || "local"
			END IF
			DEBUG(3, SFMT("File: %1 %2 %3 %4", l_arr[x].cf_or_local, l_arr[x].line_img, l_arr[x].line1, l_arr[x].line2))
		END FOR
	END IF
	CALL l_arr.sort("line1", FALSE)

	DEBUG(1, SFMT("viewDocs: Display Array, timeout is %1 rows: %2", this.mobLib.cfg.timeouts.medium, l_arr.getLength()))
	DISPLAY ARRAY l_arr TO arr.*
		BEFORE ROW
			LET x = arr_curr()
		ON ACTION back
			EXIT DISPLAY
		ON IDLE this.mobLib.cfg.timeouts.medium
			LET int_flag = TRUE
			EXIT DISPLAY
		ON ACTION enterbackground
			LET int_flag = TRUE
			EXIT DISPLAY
		ON ACTION accept
			IF l_arr[x].line_img != C_TRIMTASK_NODOC THEN
				LET l_path = this.mobLib.cfg.docPath
				IF l_arr[x].line1.getCharAt(1) = "I" OR os.path.extension(l_arr[x].line1) = "jpg" THEN
					LET l_path = this.mobLib.cfg.imgPath
				END IF
				DEBUG(1, SFMT("viewDocs: %1 %2/%3", l_arr[x].cf_or_local, l_path, l_arr[x].line1))
				IF l_arr[x].cf_or_local = "C" THEN
					IF NOT os.path.exists(os.path.join(l_path, l_arr[x].line1)) THEN
						IF NOT dbLib.getFileForJob(this.taskRec.job_link, l_path, l_arr[x].line1) THEN
						END IF
					END IF
				END IF
				IF os.path.exists(os.path.join(l_path, l_arr[x].line1)) THEN
					LET l_path = this.mobLib.showFile(l_path, l_arr[x].line1, TRUE)
				ELSE
					DEBUG(0, SFMT("viewDocs: %1/%2 not found", l_path, l_arr[x].line1))
				END IF
			END IF
	END DISPLAY
	CLOSE WINDOW taskdocs

END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Show a list of tasts for either the current user or 'other' tasks.
--
-- @param l_mine - 1=user tasks started 2=user tasks all 3=other tasks
FUNCTION (this mdTasks) showList(l_listType SMALLINT, l_autoSelect BOOLEAN) RETURNS()
	DEFINE l_titl     STRING
	DEFINE x, y       SMALLINT
	DEFINE l_ins      BOOLEAN
	DEFINE l_tasklist DYNAMIC ARRAY OF t_taskScrArr
	DEFINE l_msg      STRING
	DEFINE l_refresh  BOOLEAN

	CASE l_listType
		WHEN 1 -- current tasks that exist in trim1
			LET l_titl = "Current Tasks"
			LET l_msg  = "No Current Tasks"
		WHEN 2 -- tasks that exist exist in next_job
			LET l_titl = "Allocated Tasks"
			LET l_msg  = "You have no Allocated Tasks"
		WHEN 3 -- tasks that are not assigned to me
			LET l_titl = "Unallocated Tasks"
			LET l_msg  = "No unallocated Tasks Found"
	END CASE
	DEBUG(1, SFMT("showList: %1 - autoSelect: %2", l_titl, l_autoSelect))
	OPEN WINDOW tasks WITH FORM this.mobLib.openForm("mdTask_list")
	DISPLAY l_titl TO title

	LET int_flag = FALSE
	WHILE NOT int_flag
		IF l_listType = 3 THEN
			CALL this.getTasks(FALSE)
		ELSE
			CALL This.getTasks(TRUE)
		END IF
		CALL l_tasklist.clear()
		LET y = 0
		FOR x = 1 TO this.list.getLength()
			LET l_ins = FALSE
-- Current: trim 1 & 2 means it's been started or started and stoppped.
			IF l_listType = 1 AND this.list[x].trim < 3 AND this.list[x].my_task THEN
				LET l_ins = TRUE
			END IF
-- Active: trim 3 is a next job record only.
			IF l_listType = 2 AND this.list[x].trim > 2 AND this.list[x].my_task THEN
				LET l_ins = TRUE
			END IF
			IF l_listType = 3 AND NOT this.list[x].my_task THEN
				LET l_ins = TRUE
			END IF
			IF l_ins THEN
				LET l_tasklist[y := y + 1].line1 = this.list[x].line1
				LET l_tasklist[y].line2          = this.list[x].line2
				LET l_tasklist[y].id             = this.list[x].id
				CASE this.list[x].state
					WHEN C_TRIMTASK_STATE_NOTSTARTED
						LET l_tasklist[y].img = C_TRIMTASK_NOTSTARTED --"fa-stop-circle"
					WHEN C_TRIMTASK_STATE_STARTED
						LET l_tasklist[y].img = C_TRIMTASK_STARTED --"fa-play-circle"
					WHEN C_TRIMTASK_STATE_STOPPED
						LET l_tasklist[y].img = C_TRIMTASK_STOPPED --"fa-pause-circle"
					WHEN C_TRIMTASK_STATE_COMPLETED
						LET l_tasklist[y].img = C_TRIMTASK_COMPLETE --"fa-check-circle"
				END CASE
				IF NOT this.list[x].allowed THEN
					LET l_tasklist[y].img = C_TRIMTASK_NOTALLOWED
				END IF
			END IF
		END FOR

		LET l_refresh    = FALSE
		LET l_autoSelect = FALSE

		IF l_tasklist.getLength() = 0 THEN
			LET l_taskList[1].img   = "cancel"
			LET l_taskList[1].line1 = l_msg
			DEBUG(1, SFMT("showList: Display Array, timeout is %1", this.mobLib.cfg.timeouts.short))
			DISPLAY ARRAY l_tasklist TO scr_arr.*
				ON ACTION refresh
					LET l_refresh = TRUE
					CALL this.list.clear()
					EXIT DISPLAY
				ON IDLE this.mobLib.cfg.timeouts.short
					LET int_flag = TRUE
					EXIT DISPLAY
				ON ACTION enterbackground
					LET int_flag = TRUE
					EXIT DISPLAY
			END DISPLAY
			IF NOT l_refresh THEN
				EXIT WHILE
			END IF
		END IF

		IF l_tasklist.getLength() = 1 AND l_autoSelect THEN
			CALL this.info(l_tasklist[1].id)
			EXIT WHILE
		END IF

		DEBUG(1, SFMT("showList: Display Array, timeout is %1", this.mobLib.cfg.timeouts.medium))
		DISPLAY ARRAY l_tasklist TO scr_arr.*
			ON ACTION show ATTRIBUTES(ROWBOUND)
				CALL this.info(l_tasklist[arr_curr()].id)
			ON ACTION refresh
				LET l_refresh = TRUE
				CALL this.list.clear()
				EXIT DISPLAY
			ON ACTION info ATTRIBUTE(ROWBOUND)
				CALL stdLib.popup("Info", SFMT("Row %1 of %2", arr_curr(), l_taskList.getLength()), "information", 0)
			ON IDLE this.mobLib.cfg.timeouts.medium
				LET int_flag = TRUE
				EXIT DISPLAY
			ON ACTION enterbackground
				LET int_flag = TRUE
				EXIT DISPLAY
		END DISPLAY
		IF NOT int_flag AND NOT l_refresh THEN
			CALL this.info(l_tasklist[arr_curr()].id)
		END IF
	END WHILE
	LET int_flag = FALSE

	CLOSE WINDOW tasks
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- TODO:
FUNCTION (this mdTasks) search() RETURNS()
	OPEN WINDOW search WITH FORM this.mobLib.openForm("mdTask_search")
	DISPLAY "Search for a Job" TO menu_title
	LET int_flag = FALSE
	DEBUG(1, SFMT("search: Menu, timeout is %1", this.mobLib.cfg.timeouts.medium))
	MENU
		COMMAND "Back"
			EXIT MENU
		ON ACTION close
			EXIT MENU
		ON IDLE this.mobLib.cfg.timeouts.medium
			LET int_flag = TRUE
			EXIT MENU
		ON ACTION enterbackground
			LET int_flag = TRUE
			EXIT MENU
	END MENU
	LET int_flag = FALSE
	CLOSE WINDOW search
END FUNCTION
--------------------------------------------------------------------------------------------------------------
--
FUNCTION (this mdTasks) jobs(l_titl STRING) RETURNS()
	OPEN WINDOW jobs WITH FORM "mdTask_search"
	DISPLAY l_titl TO menu_title
	LET int_flag = FALSE
	DEBUG(1, SFMT("jobs: Menu, timeout is %1", this.mobLib.cfg.timeouts.medium))
	MENU
		COMMAND "Back"
			EXIT MENU
		ON ACTION close
			EXIT MENU
		ON IDLE this.mobLib.cfg.timeouts.medium
			LET int_flag = TRUE
			EXIT MENU
		ON ACTION enterbackground
			LET int_flag = TRUE
			EXIT MENU
	END MENU
	LET int_flag = FALSE
	CLOSE WINDOW jobs
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- load tasks from database
-- Reg-JobNo-Make/Model-Custmers Surname
FUNCTION (this mdTasks) loadArray(l_forUser BOOLEAN)
	DEFINE x, i      SMALLINT
	DEFINE l_emp     CHAR(4)
	DEFINE l_trimCmd CHAR(1)

	CALL this.list.clear()
	CALL m_TasksArr.clear()
	IF l_forUser THEN
		LET this.task_count = 0
		LET l_emp           = this.mdUser.emp_rec.short_code
	END IF
	CALL dbLib.getTaskData(this.branch, l_emp, this.job_rows, this.job_age, this.delivery, this.collection)
			RETURNING m_TasksArr
	DEBUG(1, SFMT("loadArray: got %1 rows, looking user: %2 forUser: %3 ", m_TasksArr.getLength(), l_emp, l_forUser))
	FOR x = 1 TO m_TasksArr.getLength()
		IF l_forUser THEN
			IF m_TasksArr[x].trim > 0 AND m_TasksArr[x].emp_code = this.mdUser.emp_rec.short_code
					AND m_TasksArr[x].trim_stop != "K" THEN
				CALL this.list.appendElement()
				LET i                  = this.list.getLength()
				LET this.list[i].id    = x
				LET this.list[i].state = C_TRIMTASK_STATE_NOTSTARTED
				LET this.list[i].line2 =
						"<B>" || m_TasksArr[x].work_code || "</B>", " : ", m_TasksArr[x].veh_reg CLIPPED, " ",
						m_TasksArr[x].veh_make
				LET this.list[i].line1   = m_TasksArr[x].job_number, " : ", m_TasksArr[x].contact
				LET this.list[i].my_task = TRUE
				IF m_TasksArr[x].list_status > 63 THEN -- Started ( by someone! )
					LET this.list[i].state = C_TRIMTASK_STATE_STARTED
				END IF
				LET this.list[i].allowed = this.taskAllowed(m_TasksArr[x].work_code)
				LET l_trimCmd            = m_TasksArr[x].trim_stop
				IF m_TasksArr[x].trim = 1 THEN
					LET l_trimCmd = m_TasksArr[x].trim_cmd
				END IF
				IF l_trimCmd = "S" THEN
					LET this.list[i].state = C_TRIMTASK_STATE_STARTED
				END IF
				IF l_trimCmd MATCHES "[EHP]" THEN
					LET this.list[i].state = C_TRIMTASK_STATE_STOPPED
				END IF
				-- Completed ( by someone! ) but we have trim1 with "G" somehow ?
				IF m_TasksArr[x].list_status > 127 AND m_TasksArr[x].trim_cmd != "G" THEN
					LET this.list[i].state = C_TRIMTASK_STATE_COMPLETED
				END IF
				LET this.list[i].trim = m_TasksArr[x].trim
				DEBUG(2, SFMT("loadArray: %1 %2 %3 %4 %5 %6 %7 %8", m_TasksArr[x].job_number, m_TasksArr[x].emp_code, m_TasksArr[x].work_code, m_TasksArr[x].trim, m_TasksArr[x].trim_cmd, this.list[i].state, m_TasksArr[x].list_status, m_TasksArr[x].trim_stop))
				LET this.task_count = this.task_count + 1
			END IF
		ELSE
			IF m_TasksArr[x].trim = 0 THEN
				CALL this.list.appendElement()
				LET i               = this.list.getLength()
				LET this.list[i].id = x
				LET this.list[i].line2 =
						m_TasksArr[x].work_code, ": ", m_TasksArr[x].veh_reg CLIPPED, " ", m_TasksArr[x].veh_make
				LET this.list[i].line1   = m_TasksArr[x].job_number, " ", m_TasksArr[x].contact
				LET this.list[i].my_task = FALSE
				LET this.list[i].state   = C_TRIMTASK_STATE_NOTSTARTED
			END IF
		END IF
	END FOR
	DEBUG(2, SFMT("loadArray: Populated List with %1 rows.", this.list.getLength()))
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Check the employee is allowed to start/stop/complete this task
FUNCTION (this mdTasks) taskAllowed(l_wc LIKE trim1.work_code) RETURNS BOOLEAN
	IF this.mdUser.emp_rec.tsk1 IS NULL THEN
		RETURN TRUE
	END IF
	IF this.mdUser.emp_rec.tsk1 = l_wc THEN
		RETURN TRUE
	END IF
	IF this.mdUser.emp_rec.tsk2 = l_wc THEN
		RETURN TRUE
	END IF
	IF this.mdUser.emp_rec.tsk3 = l_wc THEN
		RETURN TRUE
	END IF
	IF this.mdUser.emp_rec.tsk4 = l_wc THEN
		RETURN TRUE
	END IF
	IF this.mdUser.emp_rec.tsk5 = l_wc THEN
		RETURN TRUE
	END IF
	IF this.mdUser.emp_rec.tsk6 = l_wc THEN
		RETURN TRUE
	END IF
	IF this.mdUser.emp_rec.tsk7 = l_wc THEN
		RETURN TRUE
	END IF
	IF this.mdUser.emp_rec.tsk8 = l_wc THEN
		RETURN TRUE
	END IF
	RETURN FALSE
END FUNCTION
