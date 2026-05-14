-------------------------------------------------------------------------
-- encode data and show popup to copy it
-------------------------------------------------------------------------
function Dailies.spairs(t, order)
	-- collect the keys
	local keys = {}
	for k in pairs(t) do
		keys[Dailies.count(keys)+1] = k
	end

	-- if order function given, sort by it by passing the table and keys a, b,
	-- otherwise just sort the keys
	if order then
		table.sort(keys, function(a,b)
			return order(t, a, b)
		end)
	else
		table.sort(keys)
	end

	-- return the iterator function
	local i = 0

	return function()
		i = i + 1
		
		if keys[i] then
			return keys[i], t[keys[i]]
		end
	end
end

function Dailies.count(tab)
	local dllocal_count = 0

	for Index, Value in pairs(tab) do
		dllocal_count = dllocal_count + 1
	end

	return dllocal_count
end

function Dailies.serialize (o)
	local res = ""

	if type(o) == "number" then
		res = res .. o
	elseif type(o) == "string" then
		res = res .. string.format("%q", o)
	elseif type(o) == "table" then
		res = res .. "{ "
		for k,v in pairs(o) do
			if type(k) == "number" then
				res = res .. " [" .. k .. "] = "
			elseif type(k) == "string" then
				res = res .. " [\"" .. k .. "\"] = "
			end
		
			res = res .. Dailies.serialize(v)
			res = res .. ", "
		end
	 
		res = res .. "}"
	elseif type(o) == "boolean" then
		if o then
			res = res .. "true"
		else
			res = res .. "false"
		end
	else
		error("cannot serialize a " .. type(o))
	end

	return res
end

function Dailies.deserialize(input)
	if type(input) == 'string' then
		local data = input
		local pos = 0
	 
		function input(undo)
			if undo then
				pos = pos - 1
			else
				pos = pos + 1
				return string.sub(data, pos, pos)
			end
		end
	end

	local c

	repeat
		c = input()
	until c ~= ' ' and c ~= ','

	if c == '"' then
		--string value
		local s = ''
	 
		repeat
			c = input()
			
			if c == '"' then
				return s
			end
			
			s = s..c
		until c == ''
	elseif c == '-' or Dailies.is_digit(c) then
		-- number value
		local s = c
		
		repeat
			c = input()
			local d = Dailies.is_digit(c)
			
			if d then
				s = s..c
			end
		until not d
		
		input(true)
	 
		return tonumber(s)
	elseif c == '[' then
		--Associative
		local o = ''		
		
		repeat
			c = input()
			
			if c == ']' then
				break
			end
		
			o = o..c
		until c == ''
 
		o = o:gsub('"', "") -- removing extra ""
	 
		repeat
			c = input()
		until c == '='

		local subarr = {}
		local elem = Dailies.deserialize(input)
 
		table.insert(subarr, "assoc")
		table.insert(subarr, o)
		table.insert(subarr, elem)
		return subarr
	elseif c == '{' then
		--array
		local arr = {}
		local elem

		repeat
			elem = Dailies.deserialize(input)
 
			if type(elem) == 'table' then
				if elem[1] == "assoc" then 
					arr[elem[2]] = elem[3]
				else 
					table.insert(arr, elem)
				end
			else 
				table.insert(arr, elem)
			end
		until not elem
	 
		return arr
	end
 end

function Dailies.is_digit(c)
	return c >= '0' and c <= '9'
end

local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/' -- You will need this for encoding/decoding
-- encoding
function Dailies.enc(data)
	return ((data:gsub('.', function(x)
		local r,b='',x:byte()
	
		for i=8,1,-1 do
			r=r..(b%2^i-b%2^(i-1)>0 and '1' or '0')
		end
	
		return r;
	end)..'0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
		if (#x < 6) then
			return ''
		end
	
		local c=0
	
		for i=1,6 do
			c=c+(x:sub(i,i)=='1' and 2^(6-i) or 0)
		end
	
		return b:sub(c+1,c+1)
	end)..({ '', '==', '=' })[#data%3+1])
end

-- decoding
function Dailies.dec(data)
	data = string.gsub(data, '[^'..b..'=]', '')
	return (data:gsub('.', function(x)
		if (x == '=') then
			return ''
		end
	
		local r,f='',(b:find(x)-1)
	
		for i=6,1,-1 do
			r=r..(f%2^i-f%2^(i-1)>0 and '1' or '0')
		end
	
		return r;
	end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
		if (#x ~= 8) then
			return ''
		end
	
		local c=0
	
		for i=1,8 do
			c=c+(x:sub(i,i)=='1' and 2^(8-i) or 0)
		end
	
		return string.char(c)
	end))
end

function Dailies.formatTime(sec)
	local str = ""

	if sec ~= nil then
		local minutes, hours
	
		if (sec<60) then
			str = ""..sec.."sec"
		else
			minutes = math.floor(sec/60)
			sec = sec - (minutes*60)
		
			if (minutes<60) then
				str = ""..minutes.."min"
			else
				hours = math.floor(minutes/60)
				minutes = minutes - (hours*60)
				str = ""..hours.."h"
 
				if (minutes > 0) then
					str = str .. " "..minutes.."min"
				end
			end

			if (sec > 0) then
				str = str .. " "..sec.."sec"
			end
		end
	else
		str = ""
	end

	return str
end

function Dailies.split(str, sep)
	local t = {}
	local ind = string.find(str, sep)

	while (ind ~= nil) do
		table.insert(t, string.sub(str, 1, ind-1))
		str = string.sub(str, ind+1)
		ind = string.find(str, sep, 1, true)
	end

	if (str ~="") then
		table.insert(t, str)
	end
	
	return t
end
