using System;
using System.Threading.Tasks;
using System.Net.Http;
using System.Net.Http.Headers;
using Newtonsoft.Json;
using System.Xml;
using System.Net;
using Newtonsoft.Json.Linq;
using System.IO;
using System.Linq;
using System.Collections.Generic;

namespace PIUploadUtility
{
    class Program
    {
        static string baseurl = @"https://localhost/piwebapi/";

        static JObject creds = JObject.Parse(File.ReadAllText(@"..\..\..\..\..\credentials.json"));

        static PIWebAPIClient client = new PIWebAPIClient(creds["domain"].ToString() + @"\"+creds["username"].ToString() , creds["password"].ToString());

        static string GetWebIDByPath(string path, string resource)
        {
            string query = baseurl + resource + "?path=" + path;

            try
            {
                JObject response = client.GetRequest(query);
                return response["WebId"].ToString();
            }
            catch(Exception e)
            {
                Console.WriteLine(e.InnerException.Message);
            }

            return null;
        }

        static void CreateDatabase(XmlDocument doc, string assetserver)
        {

            string serverPath = "\\\\" + assetserver;
            string assetserverWebID = GetWebIDByPath(serverPath, "assetservers");

            string createDBQuery = baseurl + "assetservers/" + assetserverWebID + "/assetdatabases";

            Guid random = Guid.NewGuid();
            string databaseName = "Building Example-" + random.ToString();

            Object payload = new 
            {
                 Name= databaseName,
                 Description= "Example for Building Data"  
            };

            string request_body = JsonConvert.SerializeObject(payload);
            
            try
            {
                client.PostRequest(createDBQuery, request_body);
            }
            catch(Exception e)
            {
                Console.WriteLine(e.InnerException.Message);
            }
            
            string databasePath = serverPath + "\\" + databaseName;
            string databaseWebID = GetWebIDByPath(databasePath, "assetdatabases");
            string importQuery = baseurl + "assetdatabases/" + databaseWebID + "/import";

            try
            {
                client.PostRequest(importQuery, doc.InnerXml.ToString(), true);
            }
            catch(Exception e)
            {
                Console.WriteLine(e.InnerException.Message);
            }
        }

        static void CreatePIPoint(string dataserver)
        {
            string path = "\\\\PIServers[" + dataserver + "]";
            string dataserverWebID = GetWebIDByPath(path, "dataservers");
            string createPIPointQuery = baseurl + "dataservers/" + dataserverWebID + "/points";
            
            var tagDefinitions = File.ReadLines(@"..\..\tagdefinition.csv");
            string name, pointType, pointClass;

            foreach (string tagDefinition in tagDefinitions)
            {
                string[] split = tagDefinition.Split(',');
                name = split[0];
                pointType = split[1];
                pointClass = split[2];

                Object payload = new
                {
                    Name = name,
                    PointType = pointType,
                    PointClass = pointClass
                };

                string request_body = JsonConvert.SerializeObject(payload);

                try
                {
                    client.PostRequest(createPIPointQuery, request_body);
                }
                catch(Exception e)
                {
                    Console.WriteLine(e.InnerException.Message);
                }
            }
        }

        static bool IsTagExist(string dataserver)
        {
            string tagname = "VAVCO 2-09.Predicted Cooling Time";
           
            string path = "\\\\" + dataserver + "\\" + tagname;
            string getPointQuery = baseurl + "points?path=" + path;

            try
            {
                JObject result = client.GetRequest(getPointQuery);
            }
            catch(Exception e)
            {
                if (e.InnerException.Message.Contains("404"))
                    return false;
                else
                    Console.WriteLine(e.InnerException.Message);
            }
            
            return true;
        }
        static void UpdateValues(string dataserver)
        {
            
            var tags = File.ReadLines(@"..\..\tagdefinition.csv");

            foreach(string tag in tags)
            {
                string[] split = tag.Split(',');
                string tagname = split[0];
                List<string[]> entries = new List<string[]>();

                var values = File.ReadLines(@"..\..\pidata.csv");
                foreach(string value in values)
                {
                    if(value.Contains(tagname))
                    {
                        entries.Add(value.Split(','));
                    }
                }

                string path = "\\\\" + dataserver + "\\" + tagname;
                string webid = GetWebIDByPath(path, "points");
                string updateValueQuery = baseurl + "streamsets/recorded";

                List<Object> items = new List<Object>();
                foreach (string[] line in entries)
                {                    
                    Object item = new
                    {
                        Timestamp = line[3],
                        Value = line[1]
                    };
                    items.Add(item);
                }

                Object payload = new
                {
                    Items = items.ToArray(),
                    WebId = webid
                };

                string request_body = "[" + JsonConvert.SerializeObject(payload) + "]";

                try
                {
                    client.PostRequest(updateValueQuery, request_body);
                }
                catch(Exception e)
                {
                    Console.WriteLine(e.InnerException.Message);
                }
            }
        }
       
        static void Main(string[] args)
        {
            JObject config = JObject.Parse(File.ReadAllText(@"..\..\..\..\..\test_config.json"));

            string dataserver = config["PI_SERVER_NAME"].ToString();
            string assetserver = config["AF_SERVER_NAME"].ToString();

            //Create and Import Database from Building Example file
            XmlDocument doc = new XmlDocument();
            doc.Load(@"..\..\Building Example.xml");
            CreateDatabase(doc, assetserver);

            //Check for and create tags
            if (!IsTagExist(dataserver))
            {
                CreatePIPoint(dataserver);
            }

            //Update values from existing csv file
            UpdateValues(dataserver);
        }
    }
}
