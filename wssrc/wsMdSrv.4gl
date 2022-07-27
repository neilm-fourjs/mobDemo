-- This service handles getting the URL for the application based on the inbound request.

IMPORT security
IMPORT com
IMPORT util
IMPORT FGL debug
IMPORT FGL ws_lib

CONSTANT C_DBVER  = 2
CONSTANT C_SRVVER = 2

PUBLIC DEFINE myNotFound RECORD ATTRIBUTE(WSError = "Record not found")
	message STRING
END RECORD
PUBLIC DEFINE mySetFailed RECORD ATTRIBUTE(WSError = "Set Failed")
	message STRING
END RECORD

PUBLIC DEFINE serviceInfo RECORD ATTRIBUTE(WSInfo)
	title         STRING,
	description   STRING,
	termOfService STRING,
	contact RECORD
		name  STRING,
		url   STRING,
		email STRING
	END RECORD,
	version STRING
END RECORD =
		(title: "wsTrimSrv", description: "A RESTFUL backend for the mobDemo application", version: "v2",
				contact:(name: "Neil J Martin", email: "neilm@4js.com"))

PRIVATE DEFINE Context DICTIONARY ATTRIBUTE(WSContext) OF STRING

PUBLIC TYPE serverInfo RECORD
	api    VARCHAR(30),
	ip     VARCHAR(60),
	dbname VARCHAR(16),
	url    VARCHAR(80),
	added  DATETIME YEAR TO SECOND,
	info   STRING
END RECORD
PUBLIC TYPE setStatus RECORD
	stat SMALLINT,
	msg  VARCHAR(30)
END RECORD

TYPE t_ver RECORD
	dbVersion      SMALLINT,
	serviceVersion SMALLINT
END RECORD
TYPE t_list DYNAMIC ARRAY OF STRING

DEFINE m_ts CHAR(19)
--------------------------------------------------------------------------------------------------------------
#+ GET https:/<server>/<gas alias>/ws/r/trimSrvApp/trimsrv/v1/getVer
#+ result: Version of DB and Service.
PUBLIC FUNCTION v1_getVer()
		ATTRIBUTES(WSPath = "/v1/getVersion", WSGet, WSDescription = "Return the version of the service")
		RETURNS(t_Ver ATTRIBUTES(WSMedia = 'application/json'))
	DEFINE l_ver t_Ver
	LET l_ver.dbVersion      = C_DBVER
	LET l_Ver.serviceVersion = C_SRVVER
	RETURN l_ver.*
END FUNCTION
--------------------------------------------------------------------------------------------------------------
#+ GET https:/<server>/<gas alias>/ws/r/trimSrvApp/trimsrv/v1/getList/trimtest
#+ result: A list of the IP's for a specific API
PUBLIC FUNCTION v1_getList(l_api STRING ATTRIBUTE(WSParam))
		ATTRIBUTES(WSPath = "/v1/getList/{l_api}", WSGet, WSDescription = "Return a list IPs for the API.",
				WSThrows = "404:@myNotFound,500:Internal Server Error")
		RETURNS(t_list ATTRIBUTES(WSMedia = 'application/json'))
	DEFINE l_list t_list
	DEFINE x SMALLINT
	DECLARE l_cur CURSOR FOR SELECT ip FROM trimservers WHERE api = l_api ORDER BY ip
	FOREACH l_cur INTO l_list[x:=x+1]
	END FOREACH
	CALL l_list.deleteElement(x)
	IF l_list.getLength() = 0 THEN
		LET myNotFound.message = SFMT("API invalid '%1' not found", l_api)
		CALL com.WebServiceEngine.SetRestError(404, myNotFound)
	END IF
	RETURN l_list
END FUNCTION
--------------------------------------------------------------------------------------------------------------
#+ GET https:/<server>/<gas alias>/ws/r/trimSrvApp/trimsrv/v1/getURL/trimtest
#+ result: A Record that contains uesr information
PUBLIC FUNCTION v1_getURL(l_api STRING ATTRIBUTE(WSParam))
		ATTRIBUTES(WSPath = "/v1/getURL/{l_api}", WSGet, WSDescription = "Return the Application URL",
				WSThrows = "404:@myNotFound,500:Internal Server Error")
		RETURNS(serverInfo ATTRIBUTES(WSMedia = 'application/json'))
	DEFINE l_rec serverInfo = (URL: "ERROR", dbname: "None!")
	DEFINE l_ip  STRING
	IF m_ts IS NULL THEN
		LET m_ts = CURRENT YEAR TO SECOND
	END IF

	CALL ws_lib.showContext(Context)

	LET l_ip = Context["Variable-REMOTE_ADDR"] -- IP of incoming request.
{	IF LENGTH(l_rec.ip) < 2 THEN -- this is the local server name
		LET l_rec.ip = Context["Variable-SERVER_NAME"]
	END IF}

	SELECT * INTO l_rec.* FROM trimServers WHERE api = l_api AND ip = l_ip
	IF STATUS != NOTFOUND THEN
		CALL debug.output(SFMT("v1_getUrl: IP: %1 API: %2 URL: %3 DB: %4", l_ip, l_api, l_rec.url, l_rec.dbname), FALSE)
		LET l_rec.info = SFMT("found for IP %1", l_ip)
	ELSE
		SELECT * INTO l_rec.* FROM trimServers WHERE api = l_api AND ip = "any"
		IF STATUS = NOTFOUND THEN
			LET l_rec.info         = SFMT("not found API %1 for IP %2 or 'any'", l_api, l_ip)
			LET myNotFound.message = SFMT("API invalid '%1' not found", l_api)
			CALL com.WebServiceEngine.SetRestError(404, myNotFound)
		ELSE
			LET l_rec.info = SFMT("not found API %1 for IP %2 fallback to 'any'", l_api, l_ip)
		END IF
	END IF

	CALL debug.output(
			SFMT("v1_getUrl: IP: %1 API: %2 URL: %3 DB: %4 Info: %5", l_ip, l_api, l_rec.url, l_rec.dbname, l_rec.info),
			FALSE)
	RETURN l_rec.*
END FUNCTION
--------------------------------------------------------------------------------------------------------------
#+ DELETE https:/<server>/<gas alias>/ws/r/trimSrvApp/trimsrv/v1/delURL/<api>/<ip>
#+ ex: DELETE https:/<server>/<gas alias>/ws/r/trimSrvApp/trimsrv/v1/delURL/trimtest/any
#+ result: status
PUBLIC FUNCTION v1_delURL(l_api STRING ATTRIBUTE(WSParam), l_ip STRING ATTRIBUTE(WSParam))
		ATTRIBUTES(WSPath = "/v1/delURL/{l_api}/{l_ip}", WSDelete, WSDescription = "Return the Application URL",
				WSThrows = "404:@myNotFound,500:Internal Server Error")
		RETURNS(BOOLEAN ATTRIBUTES(WSMedia = 'application/json'))
	DEFINE l_rec serverInfo
	CALL debug.output(SFMT("v1_delUrl: %1", l_api), FALSE)

	TRY
		SELECT * INTO l_rec.* FROM trimServers WHERE api = l_api AND @ip = l_ip
		IF STATUS = NOTFOUND THEN
			LET myNotFound.message = SFMT("API/IP '%1/%2' not found", l_api, l_ip)
			CALL com.WebServiceEngine.SetRestError(404, myNotFound)
			RETURN FALSE
		END IF
	CATCH
		CALL debug.output(SFMT("v1_delUrl error: %1 %2", l_api, SQLERRMESSAGE), FALSE)
	END TRY

	DELETE FROM trimServers WHERE api = l_api AND @ip = l_ip
	IF STATUS != 0 THEN
		LET myNotFound.message = SFMT("API delete '%1' failed", l_api)
		CALL com.WebServiceEngine.SetRestError(404, myNotFound)
		RETURN FALSE
	END IF

	RETURN TRUE
END FUNCTION
--------------------------------------------------------------------------------------------------------------
#+ POST https:/<server>/<gas alias>/ws/r/trimSrvApp/trimsrv/v1/setURL
#+ result: status
PUBLIC FUNCTION v1_setURL(l_rec serverInfo)
		ATTRIBUTES(WSPath = "/v1/setURL", WSPost, WSDescription = "Set the Application URL",
				WSThrows = "400:@mySetFailed,500:Internal Server Error")
		RETURNS(BOOLEAN ATTRIBUTES(WSMedia = 'application/json'))

	CALL debug.output(SFMT("v1_setUrl: %1 %2 %3", l_rec.api, l_rec.dbname, l_rec.url), FALSE)
	LET l_rec.added = CURRENT
	IF l_rec.dbname IS NULL THEN
		LET mySetFailed.message = "No database name!"
		CALL debug.output(SFMT("v1_setUrl-Fail: %1", mySetFailed.message), FALSE)
		CALL com.WebServiceEngine.SetRestError(402, mySetFailed)
		RETURN FALSE
	END IF
	IF l_rec.url IS NULL THEN
		LET mySetFailed.message = "No URL!"
		CALL debug.output(SFMT("v1_setUrl-Fail: %1", mySetFailed.message), FALSE)
		CALL com.WebServiceEngine.SetRestError(402, mySetFailed)
		RETURN FALSE
	END IF
	IF l_rec.url[1, 4] != "http" THEN
		LET mySetFailed.message = "URL looks invalid!"
		CALL debug.output(SFMT("v1_setUrl-Fail: %1", mySetFailed.message), FALSE)
		CALL com.WebServiceEngine.SetRestError(402, mySetFailed)
		RETURN FALSE
	END IF
	IF l_rec.ip IS NULL THEN
		LET l_rec.ip = "any"
	END IF

	SELECT * FROM trimServers WHERE api = l_rec.api AND @ip = l_rec.ip
	IF STATUS = NOTFOUND THEN
		CALL debug.output("v1_setUrl - insert", FALSE)
		TRY
			INSERT INTO trimServers(api, ip, dbname, url, added) VALUES(l_rec.api, l_rec.ip, l_rec.dbname, l_rec.url, l_rec.added)
		CATCH
			LET mySetFailed.message = "Insert failed:", SQLERRMESSAGE
			CALL debug.output(SFMT("v1_setUrl-Fail: %1", mySetFailed.message), FALSE)
			CALL com.WebServiceEngine.SetRestError(402, mySetFailed)
			RETURN FALSE
		END TRY
	ELSE
		CALL debug.output("v1_setUrl - update", FALSE)
		TRY
			UPDATE trimServers SET (api, ip, dbname, url) = (l_rec.api, l_rec.ip, l_rec.dbname, l_rec.url)
					WHERE trimServers.api = l_rec.api AND @ip = l_rec.ip
		CATCH
			LET mySetFailed.message = "Update failed:", SQLERRMESSAGE
			CALL debug.output(SFMT("v1_setUrl-Fail: %1", mySetFailed.message), FALSE)
			CALL com.WebServiceEngine.SetRestError(402, mySetFailed)
			RETURN FALSE
		END TRY
	END IF
	IF STATUS = 0 THEN
		CALL debug.output("v1_setUrl - Success", FALSE)
	ELSE
		LET mySetFailed.message = "Failed:", SQLERRMESSAGE
		CALL debug.output(SFMT("v1_setUrl-Fail: %1", mySetFailed.message), FALSE)
		CALL com.WebServiceEngine.SetRestError(402, mySetFailed)
		RETURN FALSE
	END IF
	RETURN TRUE
END FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION checkTable(l_tab STRING) RETURNS BOOLEAN
	DEFINE l_str       STRING
	DEFINE l_cre       BOOLEAN = FALSE
	DEFINE l_dbver_cre BOOLEAN = FALSE
	DEFINE l_dbver     INTEGER
	DEFINE l_servers   DYNAMIC ARRAY OF serverInfo
	DEFINE x           SMALLINT
	LET l_tab = l_tab.toLowerCase()

	TRY
		LET l_str = "SELECT COUNT(*) FROM dbver"
		CALL debug.output(SFMT("Running: %1 ...", l_str), FALSE)
		EXECUTE IMMEDIATE l_str
	CATCH
		DISPLAY SFMT("Failed to get DB version from 'dbver': %1:%2", STATUS, SQLERRMESSAGE)
		LET l_dbver_cre = TRUE
	END TRY
	IF l_dbver_cre THEN
		TRY
			LET l_str = "CREATE TABLE dbver ( ver INTEGER )"
			CALL debug.output(SFMT("Running: %1 ...", l_str), FALSE)
			EXECUTE IMMEDIATE l_str
		CATCH
			CALL debug.output(SFMT("Failed to create table! dbver %1:%2", STATUS, SQLERRMESSAGE), FALSE)
			RETURN FALSE
		END TRY
	END IF

	LET l_str = "SELECT ver FROM dbver"
	CALL debug.output(SFMT("Running: %1 ...", l_str), FALSE)
	TRY
		DECLARE cdbver CURSOR FROM l_str
		OPEN cdbver
		FETCH cdbver INTO l_dbver
	CATCH
		CALL debug.output(SFMT("Failed get dbver! %1:%2", STATUS, SQLERRMESSAGE), FALSE)
		RETURN FALSE
	END TRY
	IF STATUS = NOTFOUND THEN
		TRY
			LET l_dbver = 1
			LET l_str   = "INSERT INTO dbver VALUES( 1 )"
			CALL debug.output(SFMT("Running: %1 ...", l_str), FALSE)
			EXECUTE IMMEDIATE l_str
		CATCH
			CALL debug.output(SFMT("Failed to insert table 'dbver' %1:%2", STATUS, SQLERRMESSAGE), FALSE)
			RETURN FALSE
		END TRY
	END IF
	CALL debug.output(SFMT("DBVER: %1.", l_dbver), FALSE)

	IF l_dbver != C_DBVER THEN
		TRY
			LET l_str = SFMT("DROP TABLE %1", l_tab)
			CALL debug.output(SFMT("Running: %1 ...", l_str), FALSE)
			EXECUTE IMMEDIATE l_str
		CATCH
			CALL debug.output(SFMT("Failed to drop table! '%1' %2:%3", l_tab, STATUS, SQLERRMESSAGE), FALSE)
		END TRY
	END IF

	TRY
		LET l_str = SFMT("SELECT COUNT(*) FROM %1", l_tab)
		CALL debug.output(SFMT("Running: %1 - checking table exists ...", l_str), FALSE)
		EXECUTE IMMEDIATE l_str
	CATCH
		DISPLAY SFMT("Failed to do initial count from '%1': %2:%3", l_tab, STATUS, SQLERRMESSAGE)
		LET l_cre = TRUE
	END TRY
	IF l_cre THEN
		TRY
			LET l_str =
					SFMT("CREATE TABLE %1 ( api VARCHAR(30), ip VARCHAR(60), dbname VARCHAR(16), url VARCHAR(80), added DATETIME YEAR TO SECOND)",
							l_tab)
			CALL debug.output(SFMT("Running: %1 ...", l_str), FALSE)
			EXECUTE IMMEDIATE l_str
		CATCH
			CALL debug.output(SFMT("Failed to create table! '%1' %2:%3", l_tab, STATUS, SQLERRMESSAGE), FALSE)
			RETURN FALSE
		END TRY
	END IF

	LET l_str = SFMT("SELECT COUNT(*) FROM %1", l_tab)
	CALL debug.output(SFMT("Running: %1 - Doing row count ...", l_str), FALSE)
	TRY
		DECLARE rowCount CURSOR FROM l_str
		OPEN rowCount
		FETCH rowCount INTO x
	CATCH
		CALL debug.output(SFMT("Failed to 2nd count from '%1' %2:%3", l_tab, STATUS, SQLERRMESSAGE), FALSE)
		RETURN FALSE
	END TRY
	IF x = 0 THEN
-- Test servers
		LET l_servers[1].api    = "mdtest"
		LET l_servers[1].ip     = "any"
		LET l_servers[1].dbname = "d1234"
		LET l_servers[1].url    = "https://generodemos.dynu.net/z/ua/r/mobDemo"
		LET l_servers[1].added  = CURRENT

		LET l_str = SFMT("INSERT INTO %1 VALUES(?, ?, ?, ? ,? )", l_tab)
		CALL debug.output(SFMT("Running: %1 ...", l_str), FALSE)
		PREPARE pre_ins FROM l_str
		FOR x = 1 TO l_servers.getLength()
			DISPLAY "Insert Server:", l_servers[x].api
			EXECUTE pre_ins USING l_servers[x].*
		END FOR
	ELSE
		DISPLAY SFMT("Found %1 Servers.", x)
	END IF

	IF l_dbver != C_DBVER THEN
		TRY
			LET l_str = SFMT("UPDATE dbver SET ver = %1", C_DBVER)
			CALL debug.output(SFMT("Running: %1 ...", l_str), FALSE)
			EXECUTE IMMEDIATE l_str
		CATCH
			CALL debug.output(SFMT("Failed to update dbver '%1' %2:%3", l_dbver, STATUS, SQLERRMESSAGE), FALSE)
			RETURN FALSE
		END TRY
	END IF

	RETURN TRUE
END FUNCTION
