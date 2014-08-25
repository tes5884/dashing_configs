require 'zabby'
require 'json'
require 'active_support/core_ext/numeric/time'

########################## CONSTANTS ##############################
SERVER = "http://192.168.1.22/zabbix"
USER = "user"
PASSWORD = "123456"
MINPRIORITY = 2
ANIMATE = 5.minutes

# Defines which Zabbix groups will be displays in which screen :
SCREENS = {
        "Screen 1" => [ "Windows Servers", "Linux servers", "Environment", "Security", "SIP", "UPS"]
}

NAMES = {
  1 => "info",
  2 => "warn",
  3 => "avrg",
  4 => "high",
  5 => "disa"
}
NAMES.default = "ok"

############################ MAIN ##################################
lastchange = Time.now
set :screens, SCREENS.keys # Pass the list of screens to HTML page

# Initialize the last count hash
lastcount = {}
SCREENS.each do | k, v |
  lastcount[k] = {}
  for i in MINPRIORITY..5
    lastcount[k][i] = 0
  end
end

# Start the scheduler
SCHEDULER.every '15s', allow_overlapping: false do

  begin
    serv = Zabby.init do
      set :server => SERVER
      set :user => USER
      set :password => PASSWORD
      login
    end
    SCREENS.each do |screen, groups|
      # Query Zabbix for current problem triggers
      result = serv.run {
      Zabby::Trigger.get(
        "filter" => {"value" => 1 },
        "min_severity" => MINPRIORITY,
        "groupids" => serv.run {Zabby::Hostgroup.get("filter" =>{"name" => groups},"preservekeys" => 0)}.keys(),
        "output" => "extend",
        "monitored" => 1,
        "withLastEventUnacknowledged" => 1,
        "skipDependent" => 1,
        "expandData" => "host",
        "expandDescription" => 1,
        "sortfield" => "lastchange",
        "sortorder" => "DESC")
      }

      triggers = {
        0 => [],
        1 => [],
        2 => [],
        3 => [],
        4 => [],
        5 => []
      }
      lastchange = {
        0 => 0,
        1 => 0,
        2 => 0,
        3 => 0,
        4 => 0,
        5 => 0
      }
      triggerlist = []

      # Parse the results
      jsonObj = JSON.parse(result.to_json)
      jsonObj.each do |j|
        prio = j["priority"].to_i
        last = j["lastchange"].to_i
        tgrid = j["triggerid"]
        tlink = SERVER + "/events.php?triggerid=" + tgrid + "&period=604800"
        hostnme = j["hostname"]
        hostnme = hostnme.gsub(/\..*$/, '') # strip domain name if necessary
        descr = j["description"]
        triggers[prio] << hostnme + " : " + descr
        status = Time.at(last) < (Time.now - ANIMATE) ? NAMES[prio] : NAMES[prio] + "-blink"
        triggerlist << {
          host: hostnme,
          trigger: descr,
          link: tlink,
          widget_class: "#{status}"
        }
        if last > lastchange[prio] then
          lastchange[prio] = last
        end
      end
      triggerlist = triggerlist.take(15) # Limit the list to 15 entries

      # Loop through priorities to populate the widgets
      for i in MINPRIORITY..5
        total = triggers[i].count
        #delta = total - lastcount[screen][i]
        #if delta != 0 then
        #  lastchange = Time.now
        #end

        # Set the color of the widget
        if total > 0 then
          #status = (delta == 0 and Time.at(lastchange[i]) < (Time.now - ANIMATE)) ? NAMES[i] : NAMES[i] + "-blink"
          status = Time.at(lastchange[i]) < (Time.now - ANIMATE) ? NAMES[i] : NAMES[i] + "-blink"
        else
          status = "ok" end

        # Limit the displayed events to 3 per widget
        list = triggers[i].uniq
        if list.count > 4 then
          list = list[0..2]
          list << "[...]"
        end

        # send the data to the widget
        send_event( screen + "_" + NAMES[i], { current: total, last: lastcount[screen][i], status: status, items: list } )

        lastcount[screen][i] = total # Copy trigger counts to last value
      end
      send_event( screen + "_list", { items: triggerlist } )
      send_event( screen + "_text", {title: screen, status: "ok"} )
    end
  rescue
    SCREENS.each do |screen, groups|
      send_event( screen + "_text", {title: "DASHBOARD IN ERROR", status: NAMES[5] + "-blink"} )
    end
  end
  
  ################################################################################################################################
####GET CPU % UTILIZATION
dc01 = serv.run { Zabby::Item.get "output" => "extend", "hostids" => "10110", "filter" => { "key_" => "perf_counter[\\Processor(_Total)\\% Processor Time]" } }
dc01Parsed = JSON.parse(dc01.to_json)
sql = serv.run { Zabby::Item.get "output" => "extend", "hostids" => "10092", "filter" => { "key_" => "perf_counter[\\Processor(_Total)\\% Processor Time]" } }
sqlParsed = JSON.parse(sql.to_json)

dc01Cpu = dc01Parsed[0]["lastvalue"].to_f.round(2)
sqlCpu = sqlParsed[0]["lastvalue"].to_f.round(2)

#################################################################################################################################
####GET RAM USAGE
#get total ram
dc01 = serv.run { Zabby::Item.get "output" => "extend", "hostids" => "10110", "filter" => { "key_" => "vm.memory.size[total]" } }
dc01RamParsed = JSON.parse(dc01.to_json)
dc01RamTotal = dc01RamParsed[0]["lastvalue"].to_f

sql = serv.run { Zabby::Item.get "output" => "extend", "hostids" => "10092", "filter" => { "key_" => "vm.memory.size[total]" } }
sqlRamParsed = JSON.parse(sql.to_json)
sqlRamTotal = dc01RamParsed[0]["lastvalue"].to_f

#get free ram
dc01 = serv.run { Zabby::Item.get "output" => "extend", "hostids" => "10110", "filter" => { "key_" => "vm.memory.size[free]" } }
dc01RamParsed = JSON.parse(dc01.to_json)
dc01RamFree = dc01RamParsed[0]["lastvalue"].to_f

sql = serv.run { Zabby::Item.get "output" => "extend", "hostids" => "10092", "filter" => { "key_" => "vm.memory.size[free]" } }
sqlRamParsed = JSON.parse(sql.to_json)
sqlRamFree = sqlRamParsed[0]["lastvalue"].to_f

#calculate % used ram
dc01RamUsed = ((dc01RamTotal-dc01RamFree)/dc01RamTotal)*100
sqlRamUsed = ((sqlRamTotal-sqlRamFree)/sqlRamTotal)*100

###################################################################################################################################
####Get HDD usage
dc01 = serv.run { Zabby::Item.get "output" => "extend", "hostids" => "10110", "filter" => { "key_" => "vfs.fs.size[D:,pfree]" } }
dc01Hdd = JSON.parse(dc01.to_json)
dc01Used = 100-(dc01Hdd[0]["lastvalue"].to_f)

sql = serv.run { Zabby::Item.get "output" => "extend", "hostids" => "10092", "filter" => { "key_" => "vfs.fs.size[D:,pfree]" } }
sqlHdd = JSON.parse(sql.to_json)
sqlUsed = 100-(sqlHdd[0]["lastvalue"].to_f)

##################################################################################################################################
###Get amount of files backed up
#MAJORNAS
mnas_bcps = serv.run { Zabby::Item.get "output" => "extend", "hostids" => "10109", "filter" => { "key_"=>"CheckBackups.Backups" } }
mnas_bcpsParsed = JSON.parse(mnas_bcps.to_json)
mnas_bcpsVal = mnas_bcpsParsed[0]["lastvalue"].to_i

mnas_rcrd = serv.run { Zabby::Item.get "output" => "extend", "hostids" => "10109", "filter" => { "key_" => "CheckBackups.Recordings" } }
mnas_rcrdParsed = JSON.parse(mnas_rcrd.to_json)
mnas_rcrdVal = mnas_rcrdParsed[0]["lastvalue"].to_i

mnas_ftp = serv.run { Zabby::Item.get "output" => "extend", "hostids" => "10109", "filter" => { "key_" => "CheckBackups.FTP" } }
mnas_ftpParsed = JSON.parse(mnas_ftp.to_json)
mnas_ftpVal = mnas_ftpParsed[0]["lastvalue"].to_i


#Offsite
ofst_bcps = serv.run { Zabby::Item.get "output" => "extend", "hostids" => "10112", "filter" => { "key_"=>"CheckBackups.Backups" } }
ofst_bcpsParsed = JSON.parse(ofst_bcps.to_json)
ofst_bcpsVal = ofst_bcpsParsed[0]["lastvalue"].to_i

ofst_rcrd = serv.run { Zabby::Item.get "output" => "extend", "hostids" => "10112", "filter" => { "key_" => "CheckBackups.Recordings" } }
ofst_rcrdParsed = JSON.parse(ofst_rcrd.to_json)
ofst_rcrdVal = ofst_rcrdParsed[0]["lastvalue"].to_i

ofst_ftp = serv.run { Zabby::Item.get "output" => "extend", "hostids" => "10112", "filter" => { "key_" => "CheckBackups.FTP" } }
ofst_ftpParsed = JSON.parse(ofst_ftp.to_json)
ofst_ftpVal = ofst_ftpParsed[0]["lastvalue"].to_i

srvDoor = serv.run { Zabby::Item.get "output" => "extend", "hostids" => "10107", "filter" => { "key_" => "climateIO3.1" } }
srvDoorPrsd = JSON.parse(srvDoor.to_json)
srvDoorVal = srvDoorPrsd[0]["lastvalue"].to_i
##################################################################################################################################
###Send events to widgets
  send_event('dc01_meter', {value: dc01Cpu})
  send_event('sql_meter', {value: sqlCpu})

  send_event('dc01_ram', {value: dc01RamUsed.round(2)})
  send_event('sql_ram', {value: sqlRamUsed.round(2)})

  send_event('dc01_hdd', {value: dc01Used.round(2)})
  send_event('sql_hdd', {value: sqlUsed.round(2)})

  mnasList = [{:label=>"Backups", :value=>mnas_bcpsVal}, {:label=>"Recordings", :value=>mnas_rcrdVal}, {:label=>"FTP", :value=>mnas_ftpVal}]
  ofstList = [{:label=>"Backups", :value=>ofst_bcpsVal}, {:label=>"Recordings", :value=>ofst_rcrdVal}, {:label=>"FTP", :value=>ofst_ftpVal}]
  diffList = [{:label=>"Backups", :value=>(mnas_bcpsVal-ofst_bcpsVal)}, {:label=>"Recordings", :value=>(mnas_rcrdVal-ofst_rcrdVal)}, {:label=>"FTP", :value=>(mnas_ftpVal-ofst_ftpVal)}]


  send_event('majornas_backups', { items: mnasList})
  send_event('offsite_backups', { items: ofstList})
  send_event('backups_diff', {items: diffList})

  if srvDoorVal == 0
    send_event('sroom_status', {text: "Closed", status: "ok"})
  else
    send_event('sroom_status', {text: "Open", status: "warning"})
  end
  
end

