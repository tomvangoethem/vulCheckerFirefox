#ruby driver of the AVC
#Prior to using, 1) gem install sys-proctable
#2) go to about:config of FF using the profile and type toolkit.startup.max_resumed_crashes in the search box. Set this value to -1/999999(very large number)

require 'sys/proctable'
require 'fileutils'
include Sys
require 'rbconfig'
is_windows = (RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/)

SLEEPTIME = 1500		#configurable: timeout.


#sanity check
if (ARGV.length != 2)
	p "wrong number of arguments. needs 2, 1st: testlist file name, 2nd: # of concurrent sessions"
	exit 
end

failedSiteFileName = ARGV[0]
numberOfSlices = ARGV[1].to_i

temp = IO.readlines(failedSiteFileName)
rawSites = temp[0]

rawSites = rawSites.chomp[21..-4]

allSites = rawSites.split("','")
#p allSites

groupSize = allSites.length/numberOfSlices

stringToWrite = "exports.testList = [['" + allSites[0]
i = 0
j = 0

for i in 0..numberOfSlices-1
	for j in 1..groupSize - 1
		stringToWrite = stringToWrite + "','" + allSites[i*groupSize+j]
	end
	if (i != numberOfSlices - 1)
		stringToWrite = stringToWrite + "'],['" + allSites[i*groupSize+j+1]
	else
		while (allSites[i*groupSize+j+1]!=nil)
			stringToWrite = stringToWrite + "','" + allSites[i*groupSize+j+1]
			j+=1
		end
	end
end
stringToWrite += "']];" 
File.open("./lib/dividedTestList.js",'w'){|f|
	f.write(stringToWrite)
}

if (!Dir.exists?("vulCheckerProfile0"))
	p "No bootstrapping profile, create one and re-run this script"
	p "Make sure the caching, popup blocker and crash reports are all turned off."
	exit
end

totalSessions = ARGV[1].to_i

def kill_process(pid)
	to_kill = Array.new
	to_kill.push(pid)
	ProcTable.ps do |proc|
		to_kill << proc.pid if to_kill.include?(proc.ppid)
	end
	Process.kill(9, *to_kill)
end

i = 0
WebSessions = 3
while (i < WebSessions)
	if (!File.exists?("lib/webServiceFile#{i}.js"))
		FileUtils.touch("lib/webServiceFile#{i}.js")
	end
	i+=1
end
i = 0
while (i < totalSessions)
	if (File.exists?("vulCheckerProfile#{i}/testResults/finished.txt"))
		i+=1
		next
	end
	if (!Dir.exists?("vulCheckerProfile#{i}"))
		FileUtils.mkdir_p("vulCheckerProfile#{i}")
		FileUtils.cp_r(Dir["vulCheckerProfile0/."],"vulCheckerProfile#{i}")
	end
	if (!Dir.exists?("vulCheckerProfile#{i}/testResults"))
		FileUtils.mkdir_p("vulCheckerProfile#{i}/testResults")
	end
	i+=1
end

pids = Array.new
currentFileCount = Array.new
previousFileCount = Array.new
finishedPids = Array.new
i = 0

while (i < totalSessions)
	if (is_windows) then pids[i] = spawn("cfx run -p vulCheckerProfile#{i}") else pids[i] = spawn("cfx run -p vulCheckerProfile#{i} -b ~/firefox/firefox") end
	currentFileCount[i] = Dir.entries("vulCheckerProfile#{i}/testResults/").length - 2		#. and .. doesn't count
	previousFileCount[i] = -1
	i+=1
	sleep(5)
end

while (true)
	i = 0
	while (i < totalSessions)
		if (File.exists?("vulCheckerProfile#{i}/testResults/finished.txt"))
			begin
				kill_process(pids[i])
				finishedPids.push(i)
				sleep(3)
			rescue Errno::ESRCH
			end
		end
		finishedPids.uniq!
		if (finishedPids.length == totalSessions)
			exit
		end
		currentFileCount[i] = Dir.entries("vulCheckerProfile#{i}/testResults/").length - 2		#. and .. doesn't count
		if (previousFileCount[i] != currentFileCount[i])
			previousFileCount[i] = currentFileCount[i]
		elsif !finishedPids.include?(i)
			begin
				kill_process(pids[i])
			rescue Errno::ESRCH
				#if we can't kill the process because the process already died, that's fine. We just want to restart the process.
			end
			sleep(10)									# wait for the child processes to close
			pids[i] = spawn "cfx run -p vulCheckerProfile#{i}"
		end
		i+=1
	end
	sleep(SLEEPTIME)
end