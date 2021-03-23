IMPORT os
IMPORT util

IMPORT FGL mobLib
IMPORT FGL stdLib
IMPORT FGL dbLib

SCHEMA bsdb

&define DEBUG( l_lev, l_msg ) IF this.mobLib.cfg.debug THEN CALL stdLib.debugOut( l_lev, __FILE__, __LINE__, l_msg ) END IF

CONSTANT C_DEFIMG     = "logo55.png"
CONSTANT C_LOCKOUT    = "Your account is currently locked out! - Please contact the office."
CONSTANT C_HOURSCHECK = "Not Available for following reason:\n%1\nPlease contact the office."

PUBLIC TYPE mdUsers RECORD
	pwd         STRING,
	state       SMALLINT, -- 0 clocked off / 1 clocked on / holiday
	clockedOn   DATETIME YEAR TO SECOND,
	active      SMALLINT,
	branch      CHAR(2),
	claim_today DECIMAL(10, 2),
	claim_wtd   DECIMAL(10, 2),
	claim_mtd   DECIMAL(10, 2),
	top_image   STRING,
	mobLib      mobLib,
	emp_rec     RECORD LIKE emp01.*
END RECORD
DEFINE m_branches dbLib.t_branches

FUNCTION tu_dummy()
	WHENEVER ERROR CALL app_error
END FUNCTION

--------------------------------------------------------------------------------------------------------------
FUNCTION (this mdUsers) init(l_mobLib moblib INOUT) RETURNS(mdUsers)
	INITIALIZE this.emp_rec TO NULL
	INITIALIZE this TO NULL
	LET this.top_image = C_DEFIMG
	LET this.mobLib    = l_mobLib
	RETURN this
END FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION (this mdUsers) login(l_titl STRING, l_info STRING) RETURNS BOOLEAN
	DEFINE l_usr      STRING
	DEFINE l_pwd      STRING
	DEFINE l_showPass BOOLEAN = FALSE
	DEFINE l_attempts SMALLINT = 0
	DEFINE l_msg      STRING

	OPEN FORM login FROM this.mobLib.openForm("mdLogin")
	DISPLAY FORM login
	DISPLAY l_titl TO titl
	IF l_info IS NOT NULL THEN
		CALL ui.Window.getCurrent().getForm().setFieldHidden("formonly.info", FALSE)
		DISPLAY l_info TO info
	END IF
	LET int_flag = FALSE
	DEBUG(1, "login: Input, timeout is: " || this.mobLib.cfg.timeouts.login)
	INPUT l_usr, l_pwd, this.branch FROM usr, pwd, brn ATTRIBUTES(WITHOUT DEFAULTS, UNBUFFERED)
		BEFORE INPUT
			CALL DIALOG.setFieldActive("brn", FALSE)

		AFTER FIELD pwd
			IF int_flag THEN
				EXIT INPUT
			END IF
			IF l_pwd IS NOT NULL THEN
				IF NOT this.findEmployee(l_usr) THEN
					LET l_attempts = l_attempts + 1
					DEBUG(3, SFMT("Login attempt: %1", l_attempts))
					IF l_attempts = 3 THEN
						CALL this.mobLib.exitProgram("Invalid login attempts", 1)
					END IF
					NEXT FIELD usr
				END IF
				IF m_branches.getLength() > 1 THEN -- only enable branch if more than one.
					CALL DIALOG.setFieldActive("brn", TRUE)
				END IF
				IF this.branch IS NULL AND m_branches.getLength() > 0 THEN
					LET this.branch = m_branches[1].branch_code
				END IF
			END IF

		ON ACTION showpass
			CALL stdLib.toggleShowPass(DIALOG.getForm().findNode("FormField", "formonly.pwd").getFirstChild(), l_showPass)
			LET l_showPass = NOT l_showPass

		ON ACTION test
			IF stdLib.confirm("Testing something", TRUE, 600) THEN
				CALL stdLib.popup("Info", "Accepted", "information", 600)
			ELSE
				CALL stdLib.popup("Info", "Cancelled", "information", 600)
			END IF

		ON ACTION about
			CALL this.mobLib.about()

		ON ACTION enterbackground
			CALL this.mobLib.exitProgram("login - enterbackground", 0)

		ON IDLE this.mobLib.cfg.timeouts.login
			CALL this.mobLib.timeout("Login")

		AFTER INPUT
			IF int_flag THEN
				EXIT INPUT
			END IF
			IF this.branch IS NULL THEN
				NEXT FIELD brn
			END IF
			IF NOT this.checkEmployee("L", l_usr, l_pwd) THEN
				CALL stdLib.error("Invalid Login Details", TRUE)
				NEXT FIELD usr
			END IF
			LET dbLib.m_db_moblib = this.mobLib
			LET l_msg             = dbLib.logDeviceLogin(l_usr, this.branch, NULL, TRUE)
			IF l_msg IS NOT NULL THEN
				CALL stdLib.error(l_msg, TRUE)
				NEXT FIELD usr
			END IF
	END INPUT
	IF int_flag THEN
		CALL this.mobLib.exitProgram("Login cancelled", 0)
	END IF

	CALL dbLib.isClockedOn(this.emp_rec.short_code, this.branch) RETURNING this.state, this.clockedOn
	DEBUG(1, SFMT("User: %1 - %2 Branch: %3 State: %4", this.emp_rec.short_code, this.emp_rec.full_name, this.branch, this.state))

	RETURN TRUE
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Check that the Employee is able to do something.
-- @param l_what = 'L' login checks / 'C' Clock On checks / 'S' Start Task
FUNCTION (this mdUsers) checkEmployee(l_what CHAR(1), l_usr LIKE emp01.short_code, l_pwd STRING) RETURNS BOOLEAN
	DEFINE l_ok      BOOLEAN
	DEFINE l_reason  STRING
	DEFINE l_temp_dt DATETIME YEAR TO SECOND
	DEFINE l_img     STRING

-- Sanity checks
	IF l_usr IS NULL THEN
		LET l_usr = this.emp_rec.short_code
	END IF
	IF l_usr IS NULL THEN
		DEBUG(3, "checkEmployee: No user passed!")
		RETURN FALSE
	END IF
	IF this.branch IS NULL THEN
		DEBUG(3, "checkEmployee: No branch!")
		RETURN FALSE
	END IF

	LET this.top_image = C_DEFIMG

-- we re/read the Employee here incase something changed.
	CALL dbLib.getEmployee(l_usr, this.branch, l_pwd) RETURNING this.emp_rec.*
	IF this.emp_rec.short_code IS NULL THEN -- Invalid Employee or Password
		DEBUG(3, "checkEmployee: getEmployee returned null!")
		RETURN FALSE
	END IF
	IF l_what = "L" OR l_what = "C" OR l_what = "S" THEN -- Login or Clock On or Start task
		IF this.emp_rec.lockout THEN
			CALL stdLib.popup("Lockout", C_LOCKOUT, "exclamation", 0)
			RETURN FALSE
		END IF
	END IF

	IF this.emp_rec.image_flag = "Y" THEN
		LET l_img =
				os.path.join(
						os.path.join(this.mobLib.cfg.imgPath, "emp_images"), SFMT("%1.jpg", DOWNSHIFT(this.emp_rec.short_code)))
		IF os.path.exists(l_img) THEN
			LET this.top_image = l_img
		END IF
		LET l_img =
				os.path.join(
						os.path.join(this.mobLib.cfg.imgPath, "emp_images"), SFMT("%1.png", DOWNSHIFT(this.emp_rec.short_code)))
		IF os.path.exists(l_img) THEN
			LET this.top_image = l_img
		END IF
	END IF

	DEBUG(3, "checkEmployee: getEmployee returning true!")
	RETURN TRUE
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Get the employee based on the ID and populate the branch combo if they have multiple branches.
FUNCTION (this mdUsers) findEmployee(l_empCode STRING) RETURNS BOOLEAN
	DEFINE l_ok BOOLEAN
	DEFINE l_cb ui.ComboBox
	DEFINE x    SMALLINT

	CALL m_branches.clear()
	LET this.branch = NULL
	LET l_empCode   = l_empCode.toUpperCase()
	CALL dbLib.checkEmployee(l_empCode) RETURNING l_ok, m_branches
	IF NOT l_ok THEN
		CALL stdLib.error("Invalid Login Details", TRUE)
		RETURN FALSE
	END IF -- Update UI with Branch
	LET l_cb = ui.ComboBox.forName("formonly.brn")
	CALL l_cb.clear()
	FOR x = 1 TO m_branches.getLength()
		CALL l_cb.addItem(m_branches[x].branch_code CLIPPED, m_branches[x].branch_name CLIPPED)
	END FOR

	RETURN TRUE
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Clock the user on or off
FUNCTION (this mdUsers) clockEvent() RETURNS()
	DEFINE l_stat  BOOLEAN
	DEFINE l_state SMALLINT
	LET l_state = this.state

	CALL dbLib.isClockedOn(this.emp_rec.short_code, this.branch) RETURNING this.state, this.clockedOn
	DEBUG(1, SFMT("clockEvent, timeout: %1 Internal State: %2 DB State: %3 ", this.mobLib.cfg.timeouts.confirm, l_state, this.state))
	IF l_state != this.state THEN
		-- the state changed, they clocked in/out somewhere else ?
		-- handle this and give a nice message to let them know.
		RETURN
	END IF

	IF this.state = 1 THEN
		IF NOT stdLib.confirm("Do you want to clock off?", FALSE, this.mobLib.cfg.timeouts.confirm) THEN
			RETURN
		END IF
	END IF
	LET this.state = NOT this.state

	IF this.state THEN                                                   -- Clock On
		IF NOT this.checkEmployee("C", this.emp_rec.short_code, NULL) THEN -- Check they are allowed to clock on
			LET this.state = NOT this.state
			RETURN
		END IF
		CALL dbLib.clockOn(this.emp_rec.*) RETURNING l_stat, this.active
		IF NOT l_stat THEN
			CALL stdLib.error("Clock On Failed!", TRUE)
			LET this.state = NOT this.state
		ELSE
			IF this.active > 0 THEN
				CALL stdLib.popup("Tasks Found", SFMT("You have %1 active task(s)", this.active), "information", 0)
			END IF
		END IF
		DEBUG(1, SFMT("clockEvent - On  Stat: %1 Active: %2", l_stat, this.active))
	ELSE -- Clock Off
		IF NOT dbLib.clockOff(this.emp_rec.*) THEN
			CALL stdLib.error("Clock Off Failed!", TRUE)
			LET this.state = NOT this.state
			RETURN
		END IF
		DEBUG(1, "clockEvent - Off Okay")
	END IF
	CALL dbLib.isClockedOn(this.emp_rec.short_code, this.branch) RETURNING this.state, this.clockedOn
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Return the info string for the user
FUNCTION (this mdUsers) userInfoLine() RETURNS STRING
	DEFINE l_line STRING
	LET l_line = "Hello " || this.emp_rec.full_name || " You are " || IIF(this.state, "Clocked On", "Clocked Off")
	RETURN l_line
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Enquire on the Employee
FUNCTION (this mdUsers) emp_enq()
	DEFINE l_current, l_allocated SMALLINT

	CALL dbLib.claimedTime(this.emp_rec.short_code) RETURNING this.claim_mtd, this.claim_wtd, this.claim_today

	CALL dbLib.activeTasks(this.emp_rec.short_code, this.branch) RETURNING l_current, l_allocated
	OPEN WINDOW emp_enq WITH FORM this.mobLib.openForm("trimEmpEnq")
	DISPLAY BY NAME this.emp_rec.full_name, this.clockedOn, this.claim_today, this.claim_wtd, this.claim_mtd
	DISPLAY l_allocated TO allocated_tasks
	DISPLAY l_current TO active
	DEBUG(1, SFMT("emp_enq: Menu, timeout is: %1", this.mobLib.cfg.timeouts.medium))
	MENU
		ON ACTION enterbackground
			EXIT MENU
		ON IDLE this.mobLib.cfg.timeouts.medium
			EXIT MENU
		COMMAND "Back"
			EXIT MENU
		ON ACTION close
			EXIT MENU
	END MENU
	LET int_flag = FALSE
	CLOSE WINDOW emp_enq
END FUNCTION
