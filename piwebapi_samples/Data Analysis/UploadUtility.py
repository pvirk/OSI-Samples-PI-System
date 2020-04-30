import requests
import json
import xml.etree.ElementTree as ET

from requests.auth import HTTPBasicAuth
from requests_kerberos import HTTPKerberosAuth

security_method = "basic"

def call_security_method(security_method, user_name, user_password):
    
    if security_method.lower() == 'basic':
        security_auth = HTTPBasicAuth(user_name, user_password)
    else:
        security_auth = HTTPKerberosAuth(mutual_authentication='REQUIRED',
                                         sanitize_mutual_error_response=False, delegate = True)

    return security_auth

def get(query):
    
    with open("C:/Users/student01.PISCHOOL/Desktop/pi-web-api.sandbox/msingh/credentials.json") as c:
        data = json.load(c)
        username = data['username']
        password = data['password']
        domain = data['domain']
    
    security_auth = call_security_method(security_method, domain + "\\" + username , password)
    response = requests.get(query, auth= security_auth, verify=False)

    return response

def post(query, body):
    
    header = {
        'content-type': 'application/json',
        'X-Requested-With':'XmlHttpRequest'
    }
    with open('credentials.json') as c:
        data = json.load(c)
        username = data['username']
        password = data['password']
        domain = data['domain']
        
    security_auth = call_security_method(security_method, domain + "\\" + username , password)
    response = requests.post(query, auth= security_auth, verify=False, json=body, headers=header)
    print(response.status_code)
    return response

def getDatabaseWebID(path):
    getDatabaseQuery = "https://localhost/piwebapi/assetdatabases?path=" + path
    database = json.loads(get(getDatabaseQuery).text)
    return database['WebId']

def getDataserverWebID(path):
    getDataserverQuery = "https://localhost/piwebapi/dataservers?path=" + path
    dataserver = json.loads(get(getDataserverQuery).text)
    print(dataserver['WebId'])
    return dataserver['WebId']

def createDB(body):
    path = "\\\\PIServers[PISRV01]"
    webid = getDataserverWebID(path)
    createDBQuery = "https://localhost/piwebapi/assetservers/" + webid + "/assetdatabases"
    request_body = {
            'Name': 'Building Example',
            'Description': 'Example Database for Building',
            'ExtendedProperties': {}
        } 
    post(createDBQuery, request_body)

    databasePath = "\\\\PISRV01\\Building Example"
    databaseWebID = getDatabaseWebID(databasePath)
    importQuery = "https://localhost/piwebapi/assetdatabases/"  + databaseWebID + "/import"
    post(importQuery, body)

def createPIPoint(body):
    createPIPointQuery = "https//localhost/piwebapi/dataservers/dataserver-webid/points"
    post(createPIPointQuery, body)

def updateValues(body):
    updateValueQuery = "https://localhost/piwebapi/streams/attribute-webid/value"
    post(updateValueQuery, body)

xmldoc = ET.parse('Building Example.xml')
createDB(xmldoc)




    

