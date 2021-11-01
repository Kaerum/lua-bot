local getenv = require('os').getenv


--TODO: REDO MUSIC UPDATE LOOP ITS TOO CONFUSING
local wrap,running,resume,yield = coroutine.wrap, coroutine.running,coroutine.resume,coroutine.yield

local Music = {
	name = "Music",
	guilds = {},
	TIMEOUT = 1000 * 60 * 5
}



local insert,remove = table.insert,table.remove
--[[Music object = {title,url,requester,textchannel}]]
--[[Queue = { index, musobject}]]
--[[ Guild : {
		queue = {}
		currentlyPlaying = nil
		history = {}
		connection = nil,
		soundObject = nil
}]]

function Music:getGuild(id)
	if not self.guilds[id] then
		self.guilds[id] = {
			queue = {},
			currentlyPlaying = nil,
			history = {},
			connection = nil,
			soundObject = nil
		}
	end
	return self.guilds[id]
end

function Music.addToQueue(self, args, requester, textchannel, voiceChannel, guildId)
	--FIRST WE SEE IF ITS A VALID URL OR SEARCH REQUEST THEN WE PUT IT IN THE QUEUE!

	--Search for Arguments, remove them from the argument table and return a string literal
	local literal = nil

	local possibleArguments = {
		playlist = false
	}	

	for _,v in ipairs(args) do
		if possibleArguments[v:lower()] == false then
			possibleArguments[v:lower()] = true
		else
			if literal then literal = literal .."+".. v else literal = v end
		end
	end
	if possibleArguments.playlist then
		return false, "Playlists are nor supported atm."
	end

	--Create a placeholder sound object
	local soundObject = {url=nil,id=nil,title=nil,duration=nil,requester=requester,textchannel=textchannel,voicechannel=voiceChannel}
	soundObject.url = YoutubeHelper:getURL(literal)
	if not soundObject.url then print("F") return false, "Unable to find any media." end
	local guild = self:getGuild(guildId)
	insert(guild.queue, soundObject)
	self:warn(' inserted ',  soundObject ,' to guild ' .. guildId)
	if not guild.currentlyPlaying then
		guild.currentlyPlaying = (remove(guild.queue,1))
		self:update(false, guildId)
	end
	local info = YoutubeHelper:getInfoFromURL(soundObject.url,soundObject)

	if info then
		soundObject.title = info.title
		soundObject.duration = info.duration
		soundObject.id = info.id
		soundObject.thumbnail = info.thumbnail
	end
	
	if soundObject.infoNeedsBroadcast then
		soundObject.textchannel:send{embed = Response.embeds.youtube.nowPlaying(soundObject)}
	else
		soundObject.textchannel:send{embed = Response.embeds.youtube.addedList(soundObject, 1)}--Temporarily only handles single musics
	end
	return true
	--[[if args[1]:find("soundcloud") then 
		insert(self._queue,{id=args[1],title="Soundcloud song",duration = ":)",requester=requester,textchannel=textchannel,voicechannel = voiceChannel}) 			
		if not self._currentlyPlaying then 
			self._currentlyPlaying = (remove(self._queue,1))
			self:update()
		end
 		return true
 	end

	local infoMessage
	local obj = YoutubeHelper:getMusicId(args)
	if not obj or not obj[1] then return false, "Invalid url or search" end

	local thread = running()
	wrap(function()
		for k,v in ipairs(obj) do

			local temp = YoutubeHelper:getInfoFromId(v)

			if not temp then insert(self._queue,{id=v,requester = requester,textchannel = textchannel, voicechannel =voiceChannel})
			else insert(self._queue,{id=temp.id,title=temp.title,duration=YoutubeHelper:uglyFormat(temp.duration),requester = requester,textchannel = textchannel, voicechannel =voiceChannel}) end
			
			if not infoMessage then infoMessage = textchannel:send{embed = Response.embeds.youtube.addedList(self._queue[#self._queue], k)}
			else infoMessage:setEmbed(Response.embeds.youtube.addedList(self._queue[#self._queue], k)) end
			
			if not self._currentlyPlaying then 
				self._currentlyPlaying = (remove(self._queue,1))
				self:update()
			end
		end
	end)()
	return true--]]
end

function Music:stop(guildId)
	local guild = self:getGuild(guildId)
	local s = true
	local e 
	wrap(function()
		if not guild.currentlyPlaying then s = false e = "There is nothing to stop" return 
		else 
			guild.queue = {}
			guild.currentlyPlaying = nil
			if guild.connection then 
				guild.connection:close()
				guild.connection = nil
			end
		end
	end)()
	return s,e
end

function Music:skip(guildId)
	local guild = self:getGuild(guildId)
	if not guild.currentlyPlaying then 
		return false, "There is nothing to skip"
	else
		guild.connection:stopStream()
	end
	return true
end

function Music:warn(string,info)
	if not info then 
		self.Logger:log(self.Enums.logLevel.warning,("[Music] "..string))
	else
		self.Logger:log(self.Enums.logLevel.debug, ("[Music] "..string))
	end
end

function Music:__init()
	self._ytHelper = YoutubeHelper
	self.Logger = self.Deps.Logger
	self.Client = self.Deps.Client
	self.Logger = self.Deps.Logger
	self.Enums = self.Deps.Enums
	self.Config = self.Deps.Config
	self.Discordia = self.Deps.Discordia
	self.Json = self.Deps.Json
	self.DEVKEY = getenv("YOUTUBE_KEY")
	self.Timer = self.Deps.Timer
	return Music
end

function Music:update(eos, guildId)
	--Check if there is a music queued to play right now
	--if not eos then eos = false end
	local guild = Music:getGuild(guildId)
wrap(function()
	if eos then
		insert(guild.history, guild.currentlyPlaying)
		guild.currentlyPlaying = remove(guild.queue,1)
		if not guild.currentlyPlaying then
			if guild.connection then
				self.Timer.setTimeout(self.TIMEOUT, function()
					if not guild.currentlyPlaying and #guild.queue <= 0 then
						wrap(function() 
							guild.connection:close()
							guild.connection = nil
						end)()
					end
				end)
			end
			return false, "Queue is empty, set timer to close connections!"
		else
			self:update(false, guildId)
		end
	else
		if guild.currentlyPlaying then
			if not guild.connection then
				guild.connection = guild.currentlyPlaying.voicechannel:join()
				self:update(false, guildId)
			else
				if guild.history[#guild.history] then
					if guild.currentlyPlaying.voicechannel.id ~= guild.history[#guild.history].voicechannel.id then
						guild.connection:close()
						guild.connection = guild.currentlyPlaying.voicechannel:join()
					end
				end
				if guild.currentlyPlaying.title and guild.currentlyPlaying.duration then 
					guild.currentlyPlaying.textchannel:send{embed = Response.embeds.youtube.nowPlaying(guild.currentlyPlaying)}
				else
					guild.currentlyPlaying.infoNeedsBroadcast = true
				end
				guild.connection:playYoutube(guild.currentlyPlaying.url)
				self:update(true, guildId)
			end
		else
			self:update(true, guildId)
		end
	end
end)()
end

return Music