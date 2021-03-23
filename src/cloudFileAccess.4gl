IMPORT util
IMPORT com
IMPORT xml
IMPORT os
IMPORT security
IMPORT FGL stdLib

SCHEMA bsdb

&define DEBUG( l_lev, l_msg ) IF this.debug THEN CALL stdLib.debugOut( l_lev, __FILE__, this.errLine, l_msg ) END IF

PUBLIC TYPE cloudFiles RECORD
	cono             CHAR(4),
	branch           LIKE bra01.branch_code,
	cloudStoreActive BOOLEAN,
	user_id          LIKE users.user_id,
	job_link         LIKE job01.job_link,
	token            STRING,
	token_expires    DATETIME YEAR TO SECOND,
	auth_url         STRING,
	storage_url      STRING,
	containers DYNAMIC ARRAY OF RECORD
		name  STRING,
		count SMALLINT,
		bytes INTEGER
	END RECORD,
	files DYNAMIC ARRAY OF RECORD
		name  STRING,
		type  STRING,
		hash  STRING,
		bytes INTEGER
	END RECORD,
	last_error STRING,
errLine SMALLINT,
	apiKey     STRING,
	apiUser    STRING,
	debug      SMALLINT
END RECORD

FUNCTION cfa_dummy()
	WHENEVER ERROR CALL app_error
END FUNCTION

FUNCTION (this cloudFiles) init(l_cono CHAR(4), l_branch LIKE bra01.branch_code) RETURNS BOOLEAN
	DEFINE l_cf_access_ext RECORD LIKE cf_access_ext.*
	DEFINE x               SMALLINT
	DEFINE l_connection RECORD
		name             STRING,
		url              STRING,
		url_resolved     STRING,
		user             STRING,
		key              STRING,
		auth_token       STRING,
		storage_url      STRING,
		storage_resolved STRING,
		client_proxy     STRING
	END RECORD
	DISPLAY "DEBUG:", this.debug
	CALL this.setError(__LINE__,SFMT("init: %1, %2 debug: %3", l_cono, l_branch, this.debug))
	LET this.cono             = l_cono
	LET this.branch           = l_branch
	LET this.cloudStoreActive = FALSE

	IF NOT b_value("CLOUDSTORE_ACTIVE") THEN
		CALL this.setError(__LINE__,"init: ERROR: Cloudstore not active")
		RETURN FALSE
	END IF
	LET this.cloudStoreActive = TRUE

	LET l_connection.name             = c_value("CLOUDSTORE_PROVIDER")
	LET l_connection.url              = c_value("CLOUDSTORE_URL")
	LET l_connection.user             = c_value("CLOUDSTORE_USER")
	LET l_connection.key              = c_value("CLOUDSTORE_APIKEY")
	LET l_connection.auth_token       = c_value("CLOUDSTORE_AUTH_TOKEN")
	LET l_connection.storage_url      = c_value("CLOUDSTORE_STORAGE_URL")
	LET l_connection.client_proxy     = c_value("CLOUDSTORE_CLI_PROXY")
	LET l_connection.storage_resolved = l_connection.storage_url

	SELECT COUNT(*) INTO x FROM cf_access_ext
	IF x > 0 THEN
		DECLARE sel_cf_access_ext CURSOR FOR
				SELECT * FROM cf_access_ext WHERE cf_access_ext.cf_seq_no IS NOT NULL ORDER BY cf_seq_no ASC
		FOREACH sel_cf_access_ext INTO l_cf_access_ext.*
			LET l_connection.user             = l_cf_access_ext.userid
			LET l_connection.key              = l_cf_access_ext.apikey
			LET l_connection.auth_token       = l_cf_access_ext.auth_token
			LET l_connection.storage_url      = l_cf_access_ext.storage_url
			LET l_connection.url_resolved     = l_connection.url
			LET l_connection.storage_resolved = l_connection.storage_url
		END FOREACH
	END IF
	IF NOT l_connection.storage_resolved MATCHES "https:*" THEN
		LET l_connection.storage_resolved = "https:" || l_connection.storage_resolved
	END IF
	LET this.token       = l_connection.auth_token CLIPPED
	LET this.auth_url    = l_connection.url CLIPPED
	LET this.storage_url = l_connection.storage_resolved CLIPPED
	LET this.apiKey      = l_connection.key CLIPPED
	LET this.apiUser     = l_connection.user CLIPPED

	RETURN TRUE
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- set up the context based on the job_link
FUNCTION (this cloudFiles) getContext(l_jl LIKE job01.job_link) RETURNS STRING
	DEFINE l_job01   RECORD LIKE job01.*
	DEFINE l_dte     STRING
	DEFINE l_context STRING

	IF NOT this.cloudStoreActive THEN
		RETURN FALSE
	END IF

	IF this.token_expires IS NULL OR this.token_expires < CURRENT THEN
		IF NOT this.getToken() THEN
			RETURN FALSE
		END IF
	END IF

	CALL this.setError(__LINE__,"getContext: Okay")
	LET this.job_link = l_jl
	IF this.job_link IS NULL OR this.job_link = 0 THEN
		CALL this.setError(__LINE__,"getContext: ERROR: No job_link")
		RETURN NULL
	END IF
	SELECT * INTO l_job01.* FROM job01 WHERE job_link = this.job_link
	IF STATUS = NOTFOUND THEN
		CALL this.setError(__LINE__,SFMT("getContext: ERROR: Not found job_link %1", this.job_link))
		RETURN NULL
	END IF
	LET l_dte = util.datetime.FORMAT(l_job01.created_date, "%Y-%b")
-- -d "/data/1234/jobs/A/2021/Jan/0000335856" -p "READONLY" -u nm991234   -l "/jobs/A/2021/Jan/0000335856" -j 335856 -t "A21010073 / V62JXN
	LET l_context = SFMT("data-%1-jobs-%2-%3-%4", this.cono, this.branch CLIPPED, l_dte, this.job_link USING "&&&&&&&&&&")
	LET this.errLine = __LINE__
	DEBUG(3, SFMT("Context: %1", l_context))
	RETURN l_context
END FUNCTION
--------------------------------------------------------------------------------------------------------------
-- Get a list of files in the cloud
FUNCTION (this cloudFiles) getFileList(l_containers BOOLEAN, l_start STRING, l_context STRING) RETURNS SMALLINT
	DEFINE l_req     com.HTTPRequest
	DEFINE l_resp    com.HTTPResponse
	DEFINE l_url     STRING
	DEFINE l_xml     xml.domDocument
	DEFINE l_nl      xml.DomNodeList
	DEFINE l_n       xml.DomNode
	DEFINE l_stat    SMALLINT
	DEFINE l_objName STRING
	DEFINE x, y      SMALLINT
	CALL this.setError(__LINE__,SFMT("getFileList: %1 %2 %3", l_containers, l_start, l_context))

	IF l_containers THEN
		LET l_objName = "container"
		IF l_start IS NOT NULL THEN
			LET l_url = SFMT('%1?prefix=%2-%3', this.storage_url, l_context, l_start)
		ELSE
			LET l_url = SFMT('%1?prefix=%2', this.storage_url, l_context)
		END IF
	ELSE
		LET l_objName = "object"
		LET l_url     = SFMT('%1/%2', this.storage_url, l_context)
	END IF
	LET this.errLine = __LINE__
	DEBUG(1, SFMT("getFileList: %1", l_url))
	TRY
		LET l_req = com.HTTPRequest.Create(l_url)
		CALL l_req.setHeader("Accept", "application/xml")
		CALL l_req.setHeader("X-Auth-Token", this.token CLIPPED)
		CALL l_req.setMethod("GET")
		CALL l_req.doRequest()
		LET l_resp = l_req.getResponse()
		LET l_stat = l_resp.getStatusCode()
		IF l_stat != 200 THEN
			CALL this.setError(__LINE__,SFMT("getFileList: HTTP Error (%1) %2", l_stat, l_resp.getStatusDescription()))
			RETURN l_stat
		END IF
	CATCH
		CALL this.setError(__LINE__,SFMT("getFileList: ERROR: (%1) %2 %3", STATUS, SQLCA.SQLERRM, ERR_GET(STATUS)))
		RETURN -1
	END TRY
	LET l_xml = l_resp.getXMLResponse()
	IF l_xml IS NULL THEN
		CALL this.setError(__LINE__,"getFileList: ERROR: No XML returned")
		RETURN -1
	END IF

-- dump XML for debug
--	CALL l_xml.setFeature("format-pretty-print", "TRUE")
--	IF l_containers THEN
--		CALL l_xml.save("rs_gf_conts_" || l_context || ".xml")
--	ELSE
--		CALL l_xml.save("rs_gf_files_" || l_context || ".xml")
--	END IF

-- process the XML
	LET l_nl = l_xml.getElementsByTagName(l_objName)
	IF l_nl.getCount() = 0 THEN
		CALL this.setError(__LINE__,SFMT("getFileList: ERROR: No '%1' found!", IIF(l_containers, "Folders", "Files")))
		IF l_containers THEN -- no container shouldn't happen
			RETURN -1
		ELSE -- no files is perfectly normal.
			RETURN 0
		END IF
	END IF

	IF l_containers THEN
		CALL this.containers.clear()
		LET y = 1
		FOR x = 1 TO l_nl.getCount()
			LET l_n = l_nl.getItem(x)
			TRY
				LET this.containers[y].name = l_nl.getItem(x).getElementsByTagName("name").getItem(1).getFirstChild().toString()
				LET this.containers[y].count =
						l_nl.getItem(x).getElementsByTagName("count").getItem(1).getFirstChild().toString()
				LET this.containers[y].bytes =
						l_nl.getItem(x).getElementsByTagName("bytes").getItem(1).getFirstChild().toString()
				LET y = y + 1
			CATCH
			END TRY
		END FOR
		RETURN 0
	END IF
-- Files
	CALL this.files.clear()
	LET y = 1
	FOR x = 1 TO l_nl.getCount()
		LET l_n = l_nl.getItem(x)
		TRY
			LET this.files[y].name  = l_nl.getItem(x).getElementsByTagName("name").getItem(1).getFirstChild().toString()
			LET this.files[y].hash  = l_nl.getItem(x).getElementsByTagName("hash").getItem(1).getFirstChild().toString()
			LET this.files[y].bytes = l_nl.getItem(x).getElementsByTagName("bytes").getItem(1).getFirstChild().toString()
			LET this.files[y].type =
					l_nl.getItem(x).getElementsByTagName("content_type").getItem(1).getFirstChild().toString()
			LET y = y + 1
		CATCH
		END TRY
	END FOR

	RETURN 0
END FUNCTION
--------------------------------------------------------------------------------
-- Get a file from the cloud
FUNCTION (this cloudFiles) getFile(l_context STRING, l_file STRING) RETURNS SMALLINT
	DEFINE l_req     com.HTTPRequest
	DEFINE l_resp    com.HTTPResponse
	DEFINE l_stat    SMALLINT
	DEFINE l_url     STRING
	DEFINE l_tmpFile STRING

	CALL this.setError(__LINE__,SFMT("getFile: Started %1", l_file))
	IF os.path.exists(l_file) THEN
		CALL this.setError(__LINE__,SFMT("getFile: ERROR: '%1' file already exists!", l_file))
		RETURN -1
	END IF

	LET l_url = SFMT('%1/%2/%3', this.storage_url, l_context, l_file)
	TRY
		LET l_req = com.HTTPRequest.Create(l_url)
		CALL l_req.setHeader("X-Auth-Token", this.token CLIPPED)
		CALL l_req.setMethod("GET")
		CALL l_req.doRequest()
		LET l_resp = l_req.getResponse()
		LET l_stat = l_resp.getStatusCode()
		IF l_stat != 200 THEN
			CALL this.setError(__LINE__,SFMT("getFile: HTTP Error (%1) %2", l_stat, l_resp.getStatusDescription()))
			RETURN -1
		ELSE
			LET l_tmpFile = l_resp.getFileResponse()
		END IF
	CATCH
		CALL this.setError(__LINE__,SFMT("getFile: ERROR: (%1) %2 %3", STATUS, SQLCA.SQLERRM, ERR_GET(STATUS)))
		RETURN STATUS
	END TRY

	IF NOT os.path.copy(l_tmpFile, l_file) THEN
		CALL this.setError(__LINE__,
				SFMT("getFile: ERROR Failed to rename %1 to %2 %3 %4", l_tmpFile, l_file, STATUS, ERR_GET(STATUS)))
		RETURN -1
	ELSE
		IF NOT os.path.delete(l_tmpFile) THEN
			CALL this.setError(__LINE__,SFMT("getFile: ERROR: Failed to delete %1", l_tmpFile))
			RETURN -1
		END IF
	END IF
	CALL this.setError(__LINE__,SFMT("getFile: %1 Uploaded.", l_file))
	RETURN 0
END FUNCTION
--------------------------------------------------------------------------------
-- Upload a file to the cloud
FUNCTION (this cloudFiles) putFile(l_context STRING, l_container STRING, l_file STRING) RETURNS SMALLINT
	DEFINE l_req  com.HTTPRequest
	DEFINE l_resp com.HTTPResponse
	DEFINE l_stat SMALLINT
	DEFINE l_url  STRING
	DEFINE l_md5  STRING

	CALL this.setError(__LINE__,SFMT("putFile: Started %1", l_file))
	IF NOT os.path.exists(l_file) THEN
		CALL this.setError(__LINE__,SFMT("putFile: ERROR: '%1' file not found!", l_file))
		RETURN -1
	END IF

	LET l_md5 = this.calcMD5(l_file)
	IF l_md5 IS NULL THEN
		RETURN -1
	END IF

	IF l_container IS NOT NULL THEN
		CALL this.createContainer( l_context, l_container) RETURNING l_stat
		IF l_stat != 0 THEN
			RETURN -1
		END IF
		LET l_url = SFMT('%1/%2-%3/%4', this.storage_url, l_context, l_container, l_file)
	ELSE
		LET l_url = SFMT('%1/%2/%3', this.storage_url, l_context, l_file)
	END IF

	TRY
		LET l_req = com.HTTPRequest.Create(l_url)
		# Set additional HTTP header with name 'MyHeader', and value 'High Priority'
		CALL l_req.setHeader("ETag", l_md5)
		CALL l_req.setHeader("X-Auth-Token", this.token CLIPPED)
		CALL l_req.setMethod("PUT")
		DISPLAY SFMT("putFile: doFileRequest( %1 )", l_file)
		CALL l_req.doFileRequest(l_file)
		DISPLAY "putFile: getRepsonse()"
		LET l_resp = l_req.getResponse()
		LET l_stat = l_resp.getStatusCode()
		IF l_stat != 201 THEN
			CALL this.setError(__LINE__,SFMT("putFile: HTTP Error (%1) %2", l_stat, l_resp.getStatusDescription()))
			RETURN l_stat
		ELSE
			DISPLAY l_resp.getTextResponse()
		END IF
	CATCH
		LET l_stat = STATUS
		CALL this.setError(__LINE__,SFMT("putFile: ERROR: (%1) %2 %3", l_stat, SQLCA.SQLERRM, ERR_GET(l_stat)))
		RETURN l_stat
	END TRY
	CALL this.setError(__LINE__,SFMT("putFile: %1 Uploaded.", l_file))
	RETURN 0
END FUNCTION
--------------------------------------------------------------------------------
-- "X-%1-Meta-Createdon: %2 %3"', f_type CLIPPED, TODAY USING "dd/mm/yyyy", CURRENT HOUR TO MINUTE)
FUNCTION (this cloudFiles) createContainer(l_context STRING, l_container STRING) RETURNS SMALLINT
	DEFINE l_req  com.HTTPRequest
	DEFINE l_resp com.HTTPResponse
	DEFINE l_stat SMALLINT
	DEFINE l_url  STRING

	CALL this.setError(__LINE__,SFMT("createContainer: Started %1", l_container))

	IF l_container IS NULL THEN
		CALL this.setError(__LINE__,"createContainer: folder can't be NULL!")
		RETURN -1
	ELSE
		LET l_url = SFMT('%1/%2-%3', this.storage_url, l_context, l_container)
	END IF
	TRY
		LET l_req = com.HTTPRequest.Create(l_url)
		# Set additional HTTP header with name 'MyHeader', and value 'High Priority'
		CALL l_req.setHeader("X-Container-Meta-Createdon", TODAY USING "dd/mm/yyyy" || " " || CURRENT HOUR TO MINUTE)
		CALL l_req.setHeader("X-Auth-Token", this.token CLIPPED)
		CALL l_req.setMethod("PUT")
		CALL l_req.doRequest()
		DISPLAY "createContainer: getRepsonse()"
		LET l_resp = l_req.getResponse()
		LET l_stat = l_resp.getStatusCode()
		IF l_stat < 200 AND l_stat > 299 THEN
			CALL this.setError(__LINE__,SFMT("createContainer: HTTP (%1) %2", l_stat, l_resp.getStatusDescription()))
			RETURN l_stat
		ELSE
			DISPLAY l_resp.getTextResponse()
		END IF
	CATCH
		CALL this.setError(__LINE__,SFMT("createContainer: ERROR: (%1) %2 %3", STATUS, SQLCA.SQLERRM, ERR_GET(STATUS)))
		RETURN STATUS
	END TRY
	CALL this.setError(__LINE__,SFMT("createContainer: Created %1.", l_container))
	RETURN 0
END FUNCTION
--------------------------------------------------------------------------------
FUNCTION (this cloudFiles) getToken() RETURNS BOOLEAN
	DEFINE l_req  com.HTTPRequest
	DEFINE l_resp com.HTTPResponse
	DEFINE l_xml  xml.domDocument
	DEFINE l_node xml.DomNode
	DEFINE l_jsonRec RECORD
		auth RECORD
			apiKeyCredentials RECORD ATTRIBUTES(json_name = "RAX-KSKEY:apiKeyCredentials")
				username STRING,
				apiKey   STRING
			END RECORD
		END RECORD
	END RECORD
	LET this.last_error                           = "getToken: Started"
	LET l_jsonRec.auth.apiKeyCredentials.username = this.apiUser
	LET l_jsonRec.auth.apiKeyCredentials.apiKey   = this.apiKey
	DISPLAY "GetToken: ", util.JSON.stringify(l_jsonRec)
	DISPLAY "URL: ", this.auth_url
	TRY
		LET l_req = com.HTTPRequest.Create(this.auth_url)
		CALL l_req.setHeader("Accept", "application/xml")
		CALL l_req.setHeader("Content-type", "application/json")
		CALL l_req.setMethod("POST")
		DISPLAY SFMT("getToken: doTextRequest( %1 )", util.JSON.stringify(l_jsonRec))
		CALL l_req.doTextRequest(util.JSON.stringify(l_jsonRec))
		DISPLAY "getToken: getRepsonse()"
		LET l_resp = l_req.getResponse()
		IF l_resp.getStatusCode() != 200 THEN
			CALL this.setError(__LINE__,SFMT("getToken: HTTP Error (%1) %2", l_resp.getStatusCode(), l_resp.getStatusDescription()))
			RETURN FALSE
		ELSE
			LET l_xml = l_resp.getXMLResponse()
		END IF
	CATCH
		CALL this.setError(__LINE__,SFMT("getToken: ERROR: (%1) %2 %3", STATUS, SQLCA.SQLERRM, ERR_GET(STATUS)))
		RETURN FALSE
	END TRY

	IF l_xml IS NULL THEN
		CALL this.setError(__LINE__,"getToken: ERROR: No XML!")
		RETURN FALSE
	END IF

	TRY
--		CALL l_xml.setFeature("format-pretty-print", "TRUE")
--		CALL l_xml.save("rs.xml")
		LET l_node = l_xml.selectByXPath("//d:token", "d", "http://docs.openstack.org/identity/api/v2.0").getItem(1)
		IF l_node IS NULL THEN
			CALL this.setError(__LINE__,"getToken: ERROR: didn't find token!")
			RETURN FALSE
		END IF
		LET this.token         = l_node.getAttribute("id")
		LET this.token_expires = l_node.getAttribute("expires")
		LET l_node =
				l_xml.selectByXPath('//d:service[@name="cloudFiles"]', "d", "http://docs.openstack.org/identity/api/v2.0")
						.getItem(1)
		LET l_node           = l_node.getFirstChildElement()
		LET this.storage_url = l_node.getAttribute("publicURL")
	CATCH
		CALL this.setError(__LINE__,SFMT("getToken: ERROR: Invalid XML / not found token: %1 %2", STATUS, ERR_GET(STATUS)))
		RETURN FALSE
	END TRY
	CALL this.setError(__LINE__,SFMT("Token: %1\nExpires: %2\nURL: %3", this.token, this.token_expires, this.storage_url))
	RETURN TRUE
END FUNCTION
--------------------------------------------------------------------------------
FUNCTION (this cloudFiles) calcMD5(l_file STRING) RETURNS STRING
	DEFINE dgst     security.Digest
	DEFINE l_result STRING
	DEFINE l_img    BYTE
	LOCATE l_img IN MEMORY
	CALL l_img.readFile(l_file)
	TRY
		LET dgst = security.Digest.CreateDigest("MD5")
		CALL dgst.AddData(l_img)
		LET l_result = dgst.DoHexBinaryDigest()
	CATCH
		CALL this.setError(__LINE__,SFMT("calcMD5: ERROR: %1 %2 ", STATUS, SQLCA.SQLERRM))
		RETURN NULL
	END TRY
	RETURN l_result
END FUNCTION
--------------------------------------------------------------------------------
FUNCTION (this cloudFiles) setError(l_line SMALLINT, l_err STRING)
	LET this.errLine = l_line
	IF l_err MATCHES "*ERROR*" THEN
		DEBUG(0, l_err)
	ELSE
		DEBUG(1, l_err)
	END IF
	LET this.last_error = l_err
END FUNCTION
