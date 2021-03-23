IMPORT os
IMPORT util
IMPORT FGL stdLib

&define DEBUG( l_lev, l_msg ) IF this.debug THEN CALL stdLib.debugOut( l_lev, __FILE__, __LINE__, l_msg ) END IF

PUBLIC TYPE wc_iconMenu RECORD
	fileName STRING,
	js_str   STRING,
	debug    SMALLINT,
	menuJS RECORD
		menu DYNAMIC ARRAY OF RECORD
			text      STRING,
			image     STRING,
			imgcolour STRING,
			action    STRING,
			active    BOOLEAN
		END RECORD
	END RECORD,
	fields DYNAMIC ARRAY OF RECORD
		name STRING,
		type STRING
	END RECORD,
	useWC BOOLEAN
END RECORD

FUNCTION (this wc_iconMenu) init(l_fileName STRING, l_useWC BOOLEAN) RETURNS BOOLEAN
	IF l_fileName IS NOT NULL THEN
		LET this.fileName = l_fileName
	END IF
	LET this.useWC = l_useWC
	IF this.fileName IS NOT NULL THEN
		LET this.js_str = this.getJSfromFile(this.fileName)
		IF this.js_str IS NULL THEN
			RETURN FALSE
		END IF
		DEBUG(4, SFMT("Loading Menu from JSON file '%1'", this.fileName))
		TRY
			CALL util.JSON.parse(this.js_str, this.menuJS)
		CATCH
			CALL stdLib.popup("Error", ERR_GET(STATUS), "exclation", 0)
			RETURN FALSE
		END TRY
	ELSE
		LET this.js_str = util.JSON.stringify(this.menuJS)
	END IF
	CALL util.JSON.parse(this.js_str, this.menuJS)
	IF this.menuJS.menu.getLength() = 0 THEN
		CALL stdLib.popup("Error", "Menu array is empty!", "exclation", 0)
		RETURN FALSE
	END IF
	--DISPLAY "Menu Items:", this.menuJS.menu.getLength()
	LET this.fields[1].name = "formonly.l_iconmenu"
	LET this.fields[1].type = "STRING"
	RETURN TRUE
END FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION (this wc_iconMenu) itemActive(l_item STRING, l_active BOOLEAN) RETURNS BOOLEAN
	DEFINE x     SMALLINT
	FOR x = 1 TO this.menuJS.menu.getLength()
		IF l_item = this.menuJS.menu[x].action THEN
			DEBUG(4, SFMT("itemActive: %1 was: %2 now: %3 ", l_item, this.menuJS.menu[x].active, l_active))
			LET this.menuJS.menu[x].active = l_active
			RETURN TRUE
		END IF
	END FOR
	DEBUG(2, SFMT("itemActive: %1 not found!", l_item))
	RETURN FALSE
END FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION (this wc_iconMenu) itemText(l_item STRING, l_text STRING) RETURNS BOOLEAN
	DEFINE x     SMALLINT
	FOR x = 1 TO this.menuJS.menu.getLength()
		IF l_item = this.menuJS.menu[x].action THEN
			DEBUG(4, SFMT("itemText: %1 was: %2 now: %3 ", l_item, this.menuJS.menu[x].text, l_text))
			LET this.menuJS.menu[x].text = l_text
			RETURN TRUE
		END IF
	END FOR
	DEBUG(2, SFMT("itemActive: %1 not found!", l_item))
	RETURN FALSE
END FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION (this   wc_iconMenu) ui(l_timer SMALLINT, l_idle SMALLINT) RETURNS STRING
	DEFINE d       ui.Dialog
	DEFINE x       SMALLINT
	DEFINE l_event STRING

-- NOT USING WC THEN CALL MENU and RETURN
	IF NOT this.useWC THEN
		RETURN this.menu(l_timer, l_idle)
	END IF

-- Set up the WC Icon Menu.
	LET this.js_str = util.JSON.stringify(this.menuJS)

	LET d = ui.Dialog.createInputByName(this.fields)
	CALL d.setFieldValue(this.fields[1].name, this.js_str)

	CALL d.addTrigger("ON ACTION close")
{	IF l_timer > 0 THEN -- Waiting on FGL-5133
		CALL d.addTrigger("ON TIMER "||l_timer)
	END IF }
	IF l_idle > 0 THEN -- Waiting on FGL-5133
		CALL d.addTrigger("ON IDLE "||l_idle)
	END IF
	FOR x = 1 TO this.menuJS.menu.getLength()
		DEBUG(4, "Adding action: " || this.menuJS.menu[x].action)
		IF this.menuJS.menu[x].active THEN
			CALL d.addTrigger("ON ACTION " || this.menuJS.menu[x].action)
		END IF
	END FOR
--	CALL d.addTrigger("ON ACTION exit")
	DEBUG(1, SFMT("wc_iconMenu.ui: Menu, timeout is: %1", l_idle ))
	WHILE TRUE
		LET l_event = d.nextEvent()
		IF l_event.subString(1, 10) = "ON ACTION " THEN
			LET l_event = l_event.subString(11, l_event.getLength())
			EXIT WHILE
		END IF
		IF l_event.subString(1, 9) = "ON TIMER " THEN
			LET l_event = "timer"
			EXIT WHILE
		END IF
		IF l_event.subString(1, 8) = "ON IDLE " THEN
			LET l_event = "timeout"
			EXIT WHILE
		END IF
		CASE l_event
			WHEN "BEFORE INPUT"
				DEBUG(4, "BI")
			WHEN "BEFORE FIELD l_iconmenu"
				DEBUG(4, "BF l_iconmenu")

			OTHERWISE
				DEBUG(1, SFMT("Unhandled event: %1", l_event))
		END CASE
	END WHILE
	CALL d.close()

	RETURN l_event
END FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION (this   wc_iconMenu) menu(l_timer SMALLINT, l_idle SMALLINT) RETURNS STRING
	DEFINE l_event STRING
	DEFINE x, y, i SMALLINT
	DEFINE n om.DomNode
	LET n = ui.Window.getCurrent().getForm().getNode()
	LET y = n.selectByPath("//Button[@tag=\"menu\"]").getLength()
	DEBUG(1, SFMT("wc_iconMenu.menu: Menu, timeout is: %1", l_idle ))
	MENU
		BEFORE MENU
			LET i = this.menuJS.menu.getLength()
			FOR x = 1 TO y
				IF x > i OR this.menuJS.menu[x].text.getLength() = 0 OR this.menuJS.menu[x].text.getCharAt(1) = "_" THEN
					LET this.menuJS.menu[x].action = "opt"||x
					CALL DIALOG.getForm().setElementHidden("opt"||x, TRUE)
				ELSE
					CALL DIALOG.getForm().setElementText("opt"||x, this.menuJS.menu[x].text )
					CALL DIALOG.getForm().setElementImage("opt"||x, this.menuJS.menu[x].image )
					IF NOT this.menuJS.menu[x].active THEN
						CALL DIALOG.setActionActive("opt"||x, FALSE)
					ELSE
						CALL DIALOG.setActionActive("opt"||x, TRUE)
					END IF
				END IF
			END FOR
		ON ACTION opt1
			LET l_event = this.menuJS.menu[1].action
			EXIT MENU
		ON ACTION opt2
			LET l_event = this.menuJS.menu[2].action
			EXIT MENU
		ON ACTION opt3
			LET l_event = this.menuJS.menu[3].action
			EXIT MENU
		ON ACTION opt4
			LET l_event = this.menuJS.menu[4].action
			EXIT MENU
		ON ACTION opt5
			LET l_event = this.menuJS.menu[5].action
			EXIT MENU
		ON ACTION opt6
			LET l_event = this.menuJS.menu[6].action
			EXIT MENU
		ON ACTION opt7
			LET l_event = this.menuJS.menu[7].action
			EXIT MENU
		ON ACTION opt8
			LET l_event = this.menuJS.menu[8].action
			EXIT MENU
		ON ACTION opt9
			LET l_event = this.menuJS.menu[9].action
			EXIT MENU
		ON IDLE l_idle
			LET l_event = "timeout"
			EXIT MENU
		ON ACTION close
			LET l_event = "close"
			EXIT MENU
		ON ACTION about
			LET l_event = "about"
			EXIT MENU
	END MENU
	RETURN l_event
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Get file/path for the menu
FUNCTION (this    wc_iconMenu) getJSfromFile(l_fileName STRING) RETURNS STRING
	DEFINE l_menu   TEXT
	DEFINE l_jsFile STRING
	LET l_jsFile = os.path.join(os.path.join("..", "etc"), l_fileName)
	IF NOT os.Path.isFile(l_jsFile) THEN
		DEBUG(2, SFMT("Not found: %1", l_jsFile))
		LET l_jsFile = l_fileName
	END IF
	IF NOT os.Path.exists(l_jsFile) THEN
		DEBUG(0, SFMT("Not found: %1", l_jsFile))
		CALL stdLib.popup("Error", SFMT("JS iconMenu file '%1' not found!", l_fileName), "exclamation", 0)
		RETURN NULL
	END IF
	LET this.fileName = l_jsFile
	LOCATE l_menu IN FILE l_jsFile
	RETURN l_menu
END FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION (this wc_iconMenu) addMenuItem(l_text STRING, l_img STRING, l_act STRING, l_live BOOLEAN)
	DEFINE x     SMALLINT
	LET x                          = this.menuJS.menu.getLength() + 1
	LET this.menuJS.menu[x].text   = l_text
	LET this.menuJS.menu[x].image  = l_img
	LET this.menuJS.menu[x].action = l_act
	LET this.menuJS.menu[x].active = l_live
END FUNCTION
