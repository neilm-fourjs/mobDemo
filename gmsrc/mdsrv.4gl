#+
#+ Generated from mdsrv
#+
IMPORT com
IMPORT xml
IMPORT util
IMPORT os

#+
#+ Global Endpoint user-defined type definition
#+
TYPE tGlobalEndpointType RECORD # Rest Endpoint
	Address RECORD                # Address
		Uri STRING                  # URI
	END RECORD,
	Binding RECORD               # Binding
		Version           STRING,  # HTTP Version (1.0 or 1.1)
		ConnectionTimeout INTEGER, # Connection timeout
		ReadWriteTimeout  INTEGER, # Read write timeout
		CompressRequest   STRING   # Compression (gzip or deflate)
	END RECORD
END RECORD

PUBLIC DEFINE Endpoint tGlobalEndpointType = (Address:(Uri: "https://generodemos.dynu.net/z/ws/r/mdSrvApp/mdsrv"))

# Error codes
PUBLIC CONSTANT C_SUCCESS               = 0
PUBLIC CONSTANT C_MYSETFAILED           = 1001
PUBLIC CONSTANT C_INTERNAL_SERVER_ERROR = 1002
PUBLIC CONSTANT C_MYNOTFOUND            = 1003

# generated v1_setURLRequestBodyType
PUBLIC TYPE v1_setURLRequestBodyType RECORD
	api    STRING,
	ip     STRING,
	dbname STRING,
	url    STRING,
	added  DATETIME YEAR TO SECOND,
	info   STRING
END RECORD

# generated mySetFailedErrorType
PUBLIC TYPE mySetFailedErrorType RECORD
	message STRING
END RECORD

# generated v1_getVerResponseBodyType
PUBLIC TYPE v1_getVerResponseBodyType RECORD
	dbVersion      INTEGER,
	serviceVersion INTEGER
END RECORD

# generated myNotFoundErrorType
PUBLIC TYPE myNotFoundErrorType RECORD
	message STRING
END RECORD

# generated v1_getURLResponseBodyType
PUBLIC TYPE v1_getURLResponseBodyType RECORD
	api    STRING,
	ip     STRING,
	dbname STRING,
	url    STRING,
	added  DATETIME YEAR TO SECOND,
	info   STRING
END RECORD

# generated v1_getListResponseBodyType
PUBLIC TYPE v1_getListResponseBodyType DYNAMIC ARRAY OF STRING

PUBLIC # Set Failed
		DEFINE mySetFailed mySetFailedErrorType
PUBLIC # Record not found
		DEFINE myNotFound myNotFoundErrorType

################################################################################
# Operation /v1/setURL
#
# VERB: POST
# ID:          v1_setURL
# DESCRIPTION: Set the Application URL
#
PUBLIC FUNCTION v1_setURL(p_body v1_setURLRequestBodyType) RETURNS(INTEGER, BOOLEAN)
	DEFINE fullpath    base.StringBuffer
	DEFINE contentType STRING
	DEFINE req         com.HTTPRequest
	DEFINE resp        com.HTTPResponse
	DEFINE resp_body   BOOLEAN
	DEFINE xml_mySetFailed RECORD ATTRIBUTE(XMLName = 'mySetFailed')
		message STRING
	END RECORD
	DEFINE xml_body  xml.DomDocument
	DEFINE xml_node  xml.DomNode
	DEFINE json_body STRING
	DEFINE txt       STRING

	TRY

		# Prepare request path
		LET fullpath = base.StringBuffer.Create()
		CALL fullpath.append("/v1/setURL")

		# Create request and configure it
		LET req = com.HTTPRequest.Create(SFMT("%1%2", Endpoint.Address.Uri, fullpath.toString()))
		IF Endpoint.Binding.Version IS NOT NULL THEN
			CALL req.setVersion(Endpoint.Binding.Version)
		END IF
		IF Endpoint.Binding.ConnectionTimeout <> 0 THEN
			CALL req.setConnectionTimeout(Endpoint.Binding.ConnectionTimeout)
		END IF
		IF Endpoint.Binding.ReadWriteTimeout <> 0 THEN
			CALL req.setTimeout(Endpoint.Binding.ReadWriteTimeout)
		END IF
		IF Endpoint.Binding.CompressRequest IS NOT NULL THEN
			CALL req.setHeader("Content-Encoding", Endpoint.Binding.CompressRequest)
		END IF

		# Perform request
		CALL req.setMethod("POST")
		CALL req.setHeader("Accept", "application/json, application/xml")
		# Perform JSON request
		CALL req.setHeader("Content-Type", "application/json")
		LET json_body = util.JSON.stringify(p_body)
		CALL req.DoTextRequest(json_body)

		# Retrieve response
		LET resp = req.getResponse()
		# Process response
		INITIALIZE resp_body TO NULL
		LET contentType = resp.getHeader("Content-Type")
		CASE resp.getStatusCode()

			WHEN 200 #Success
				IF contentType MATCHES "*application/json*" THEN
					# Parse JSON response
					LET json_body = resp.getTextResponse()
					CALL util.JSON.parse(json_body, resp_body)
					RETURN C_SUCCESS, resp_body
				END IF
				RETURN -1, resp_body

			WHEN 400 #Set Failed
				IF contentType MATCHES "*application/json*" THEN
					# Parse JSON response
					LET json_body = resp.getTextResponse()
					CALL util.JSON.parse(json_body, mySetFailed)
					RETURN C_MYSETFAILED, resp_body
				END IF
				IF contentType MATCHES "*application/xml*" THEN
					# Parse XML response
					LET xml_body = resp.getXmlResponse()
					LET xml_node = xml_body.getDocumentElement()
					CALL xml.serializer.DomToVariable(xml_node, xml_mySetFailed)
					LET mySetFailed.* = xml_mySetFailed.*
					RETURN C_MYSETFAILED, resp_body
				END IF
				RETURN -1, resp_body

			WHEN 500 #Internal Server Error
				RETURN C_INTERNAL_SERVER_ERROR, resp_body

			OTHERWISE
				RETURN resp.getStatusCode(), resp_body
		END CASE
	CATCH
		RETURN -1, resp_body
	END TRY
END FUNCTION
################################################################################

################################################################################
# Operation /v1/getVersion
#
# VERB: GET
# ID:          v1_getVer
# DESCRIPTION: Return the version of the service
#
PUBLIC FUNCTION v1_getVer() RETURNS(INTEGER, v1_getVerResponseBodyType)
	DEFINE fullpath    base.StringBuffer
	DEFINE contentType STRING
	DEFINE req         com.HTTPRequest
	DEFINE resp        com.HTTPResponse
	DEFINE resp_body   v1_getVerResponseBodyType
	DEFINE json_body   STRING
	DEFINE txt         STRING

	TRY

		# Prepare request path
		LET fullpath = base.StringBuffer.Create()
		CALL fullpath.append("/v1/getVersion")

		# Create request and configure it
		LET req = com.HTTPRequest.Create(SFMT("%1%2", Endpoint.Address.Uri, fullpath.toString()))
		IF Endpoint.Binding.Version IS NOT NULL THEN
			CALL req.setVersion(Endpoint.Binding.Version)
		END IF
		IF Endpoint.Binding.ConnectionTimeout <> 0 THEN
			CALL req.setConnectionTimeout(Endpoint.Binding.ConnectionTimeout)
		END IF
		IF Endpoint.Binding.ReadWriteTimeout <> 0 THEN
			CALL req.setTimeout(Endpoint.Binding.ReadWriteTimeout)
		END IF
		IF Endpoint.Binding.CompressRequest IS NOT NULL THEN
			CALL req.setHeader("Content-Encoding", Endpoint.Binding.CompressRequest)
		END IF

		# Perform request
		CALL req.setMethod("GET")
		CALL req.setHeader("Accept", "application/json")
		CALL req.DoRequest()

		# Retrieve response
		LET resp = req.getResponse()
		# Process response
		INITIALIZE resp_body TO NULL
		LET contentType = resp.getHeader("Content-Type")
		CASE resp.getStatusCode()

			WHEN 200 #Success
				IF contentType MATCHES "*application/json*" THEN
					# Parse JSON response
					LET json_body = resp.getTextResponse()
					CALL util.JSON.parse(json_body, resp_body)
					RETURN C_SUCCESS, resp_body.*
				END IF
				RETURN -1, resp_body.*

			OTHERWISE
				RETURN resp.getStatusCode(), resp_body.*
		END CASE
	CATCH
		RETURN -1, resp_body.*
	END TRY
END FUNCTION
################################################################################

################################################################################
# Operation /v1/delURL/{l_api}/{l_ip}
#
# VERB: DELETE
# ID:          v1_delURL
# DESCRIPTION: Return the Application URL
#
PUBLIC FUNCTION v1_delURL(p_l_api STRING, p_l_ip STRING) RETURNS(INTEGER, BOOLEAN)
	DEFINE fullpath    base.StringBuffer
	DEFINE contentType STRING
	DEFINE req         com.HTTPRequest
	DEFINE resp        com.HTTPResponse
	DEFINE resp_body   BOOLEAN
	DEFINE xml_myNotFound RECORD ATTRIBUTE(XMLName = 'myNotFound')
		message STRING
	END RECORD
	DEFINE xml_body  xml.DomDocument
	DEFINE xml_node  xml.DomNode
	DEFINE json_body STRING
	DEFINE txt       STRING

	TRY

		# Prepare request path
		LET fullpath = base.StringBuffer.Create()
		CALL fullpath.append("/v1/delURL/{l_api}/{l_ip}")
		CALL fullpath.replace("{l_api}", p_l_api, 1)
		CALL fullpath.replace("{l_ip}", p_l_ip, 1)

		# Create request and configure it
		LET req = com.HTTPRequest.Create(SFMT("%1%2", Endpoint.Address.Uri, fullpath.toString()))
		IF Endpoint.Binding.Version IS NOT NULL THEN
			CALL req.setVersion(Endpoint.Binding.Version)
		END IF
		IF Endpoint.Binding.ConnectionTimeout <> 0 THEN
			CALL req.setConnectionTimeout(Endpoint.Binding.ConnectionTimeout)
		END IF
		IF Endpoint.Binding.ReadWriteTimeout <> 0 THEN
			CALL req.setTimeout(Endpoint.Binding.ReadWriteTimeout)
		END IF
		IF Endpoint.Binding.CompressRequest IS NOT NULL THEN
			CALL req.setHeader("Content-Encoding", Endpoint.Binding.CompressRequest)
		END IF

		# Perform request
		CALL req.setMethod("DELETE")
		CALL req.setHeader("Accept", "application/json, application/xml")
		CALL req.DoRequest()

		# Retrieve response
		LET resp = req.getResponse()
		# Process response
		INITIALIZE resp_body TO NULL
		LET contentType = resp.getHeader("Content-Type")
		CASE resp.getStatusCode()

			WHEN 200 #Success
				IF contentType MATCHES "*application/json*" THEN
					# Parse JSON response
					LET json_body = resp.getTextResponse()
					CALL util.JSON.parse(json_body, resp_body)
					RETURN C_SUCCESS, resp_body
				END IF
				RETURN -1, resp_body

			WHEN 404 #Record not found
				IF contentType MATCHES "*application/json*" THEN
					# Parse JSON response
					LET json_body = resp.getTextResponse()
					CALL util.JSON.parse(json_body, myNotFound)
					RETURN C_MYNOTFOUND, resp_body
				END IF
				IF contentType MATCHES "*application/xml*" THEN
					# Parse XML response
					LET xml_body = resp.getXmlResponse()
					LET xml_node = xml_body.getDocumentElement()
					CALL xml.serializer.DomToVariable(xml_node, xml_myNotFound)
					LET myNotFound.* = xml_myNotFound.*
					RETURN C_MYNOTFOUND, resp_body
				END IF
				RETURN -1, resp_body

			WHEN 500 #Internal Server Error
				RETURN C_INTERNAL_SERVER_ERROR, resp_body

			OTHERWISE
				RETURN resp.getStatusCode(), resp_body
		END CASE
	CATCH
		RETURN -1, resp_body
	END TRY
END FUNCTION
################################################################################

################################################################################
# Operation /v1/getURL/{l_api}
#
# VERB: GET
# ID:          v1_getURL
# DESCRIPTION: Return the Application URL
#
PUBLIC FUNCTION v1_getURL(p_l_api STRING) RETURNS(INTEGER, v1_getURLResponseBodyType)
	DEFINE fullpath    base.StringBuffer
	DEFINE contentType STRING
	DEFINE req         com.HTTPRequest
	DEFINE resp        com.HTTPResponse
	DEFINE resp_body   v1_getURLResponseBodyType
	DEFINE xml_myNotFound RECORD ATTRIBUTE(XMLName = 'myNotFound')
		message STRING
	END RECORD
	DEFINE xml_body  xml.DomDocument
	DEFINE xml_node  xml.DomNode
	DEFINE json_body STRING
	DEFINE txt       STRING

	TRY

		# Prepare request path
		LET fullpath = base.StringBuffer.Create()
		CALL fullpath.append("/v1/getURL/{l_api}")
		CALL fullpath.replace("{l_api}", p_l_api, 1)

		# Create request and configure it
		LET req = com.HTTPRequest.Create(SFMT("%1%2", Endpoint.Address.Uri, fullpath.toString()))
		IF Endpoint.Binding.Version IS NOT NULL THEN
			CALL req.setVersion(Endpoint.Binding.Version)
		END IF
		IF Endpoint.Binding.ConnectionTimeout <> 0 THEN
			CALL req.setConnectionTimeout(Endpoint.Binding.ConnectionTimeout)
		END IF
		IF Endpoint.Binding.ReadWriteTimeout <> 0 THEN
			CALL req.setTimeout(Endpoint.Binding.ReadWriteTimeout)
		END IF
		IF Endpoint.Binding.CompressRequest IS NOT NULL THEN
			CALL req.setHeader("Content-Encoding", Endpoint.Binding.CompressRequest)
		END IF

		# Perform request
		CALL req.setMethod("GET")
		CALL req.setHeader("Accept", "application/json, application/xml")
		CALL req.DoRequest()

		# Retrieve response
		LET resp = req.getResponse()
		# Process response
		INITIALIZE resp_body TO NULL
		LET contentType = resp.getHeader("Content-Type")
		CASE resp.getStatusCode()

			WHEN 200 #Success
				IF contentType MATCHES "*application/json*" THEN
					# Parse JSON response
					LET json_body = resp.getTextResponse()
					CALL util.JSON.parse(json_body, resp_body)
					RETURN C_SUCCESS, resp_body.*
				END IF
				RETURN -1, resp_body.*

			WHEN 404 #Record not found
				IF contentType MATCHES "*application/json*" THEN
					# Parse JSON response
					LET json_body = resp.getTextResponse()
					CALL util.JSON.parse(json_body, myNotFound)
					RETURN C_MYNOTFOUND, resp_body.*
				END IF
				IF contentType MATCHES "*application/xml*" THEN
					# Parse XML response
					LET xml_body = resp.getXmlResponse()
					LET xml_node = xml_body.getDocumentElement()
					CALL xml.serializer.DomToVariable(xml_node, xml_myNotFound)
					LET myNotFound.* = xml_myNotFound.*
					RETURN C_MYNOTFOUND, resp_body.*
				END IF
				RETURN -1, resp_body.*

			WHEN 500 #Internal Server Error
				RETURN C_INTERNAL_SERVER_ERROR, resp_body.*

			OTHERWISE
				RETURN resp.getStatusCode(), resp_body.*
		END CASE
	CATCH
		RETURN -1, resp_body.*
	END TRY
END FUNCTION
################################################################################

################################################################################
# Operation /v1/getList/{l_api}
#
# VERB: GET
# ID:          v1_getList
# DESCRIPTION: Return a list IPs for the API.
#
PUBLIC FUNCTION v1_getList(p_l_api STRING) RETURNS(INTEGER, v1_getListResponseBodyType)
	DEFINE fullpath    base.StringBuffer
	DEFINE contentType STRING
	DEFINE req         com.HTTPRequest
	DEFINE resp        com.HTTPResponse
	DEFINE resp_body   v1_getListResponseBodyType
	DEFINE xml_myNotFound RECORD ATTRIBUTE(XMLName = 'myNotFound')
		message STRING
	END RECORD
	DEFINE xml_body  xml.DomDocument
	DEFINE xml_node  xml.DomNode
	DEFINE json_body STRING
	DEFINE txt       STRING

	TRY

		# Prepare request path
		LET fullpath = base.StringBuffer.Create()
		CALL fullpath.append("/v1/getList/{l_api}")
		CALL fullpath.replace("{l_api}", p_l_api, 1)

		# Create request and configure it
		LET req = com.HTTPRequest.Create(SFMT("%1%2", Endpoint.Address.Uri, fullpath.toString()))
		IF Endpoint.Binding.Version IS NOT NULL THEN
			CALL req.setVersion(Endpoint.Binding.Version)
		END IF
		IF Endpoint.Binding.ConnectionTimeout <> 0 THEN
			CALL req.setConnectionTimeout(Endpoint.Binding.ConnectionTimeout)
		END IF
		IF Endpoint.Binding.ReadWriteTimeout <> 0 THEN
			CALL req.setTimeout(Endpoint.Binding.ReadWriteTimeout)
		END IF
		IF Endpoint.Binding.CompressRequest IS NOT NULL THEN
			CALL req.setHeader("Content-Encoding", Endpoint.Binding.CompressRequest)
		END IF

		# Perform request
		CALL req.setMethod("GET")
		CALL req.setHeader("Accept", "application/json, application/xml")
		CALL req.DoRequest()

		# Retrieve response
		LET resp = req.getResponse()
		# Process response
		INITIALIZE resp_body TO NULL
		LET contentType = resp.getHeader("Content-Type")
		CASE resp.getStatusCode()

			WHEN 200 #Success
				IF contentType MATCHES "*application/json*" THEN
					# Parse JSON response
					LET json_body = resp.getTextResponse()
					CALL util.JSON.parse(json_body, resp_body)
					RETURN C_SUCCESS, resp_body
				END IF
				RETURN -1, resp_body

			WHEN 404 #Record not found
				IF contentType MATCHES "*application/json*" THEN
					# Parse JSON response
					LET json_body = resp.getTextResponse()
					CALL util.JSON.parse(json_body, myNotFound)
					RETURN C_MYNOTFOUND, resp_body
				END IF
				IF contentType MATCHES "*application/xml*" THEN
					# Parse XML response
					LET xml_body = resp.getXmlResponse()
					LET xml_node = xml_body.getDocumentElement()
					CALL xml.serializer.DomToVariable(xml_node, xml_myNotFound)
					LET myNotFound.* = xml_myNotFound.*
					RETURN C_MYNOTFOUND, resp_body
				END IF
				RETURN -1, resp_body

			WHEN 500 #Internal Server Error
				RETURN C_INTERNAL_SERVER_ERROR, resp_body

			OTHERWISE
				RETURN resp.getStatusCode(), resp_body
		END CASE
	CATCH
		RETURN -1, resp_body
	END TRY
END FUNCTION
################################################################################
