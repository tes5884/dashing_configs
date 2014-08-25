require 'rubygems'
require 'curb'
require 'json'
require 'net/ping/http'
require 'net/ftp'
#################################################################
##############VARIABLES##########################################
http = [["http://google.com", "me_status"],["http://bing.com","rp_status"]]
apiKey = "yourAPI"
accessToken = ""

#################################################################
##############SCHEDULER##########################################
SCHEDULER.every '60s', :first_in => 0, allow_overlapping: false do
  for i in http
    p = Net::Ping::HTTP.new(i[0])
    if p.ping
      send_event(i[1], {text: "UP", status: "ok"})
    else
      send_event(i[1], {text: "DOWN", status: "warning"})
    end
  end

  test = Net::FTP.open("ftp.exavault.com")
  if test.last_response.include?("220")
    send_event("ftp_status", {text: "UP", status: "ok"})
  else
    send_event("ftp_status", {text: "DOWN", status: "warning"})
  end

end

#################################################################
##############SCHEDULER#########################################
SCHEDULER.every '30m', :first_in => 0, allow_overlapping: false do
#################################################################
#Get access token
urlAuth = "https://api.exavault.com:443/v1/authenticateUser?username=yourusername&password=yourpassword&api_key=yourapikey"
curl = Curl::Easy.new(urlAuth)
curl.perform
json_data = JSON.parse(curl.body_str)

accessToken = json_data["results"]["accessToken"]

#Get Account info
urlInfo = "https://api.exavault.com:443/v1/getAccount?access_token=" + accessToken + "&api_key=" + apiKey
curl = Curl::Easy.new(urlInfo)
curl.perform
json_data = JSON.parse(curl.body_str) 

#diskQuotaLimit
#diskQuotaUsed

percentUsedStorage = (json_data["results"]["diskQuotaUsed"].to_f/json_data["results"]["diskQuotaLimit"].to_f)*100

send_event('ftp_storage', {value: percentUsedStorage.round(2)})

end
