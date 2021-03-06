--compiles bcasm into lua 5.1 bytecode--
--also exposes helper methods to encode opcodes--
local bit = bit32 or require "bit"
if not bit.blshift then
	bit.blshift = bit.lshift
	bit.brshift = bit.rshift
end

compiler = {}
compiler.debug = false

local function debug(...)
	if compiler.debug then
		print(...)
	end
end

local instructionNames = {
	[0]="MOVE","LOADK","LOADBOOL","LOADNIL",
	"GETUPVAL","GETGLOBAL","GETTABLE",
	"SETGLOBAL","SETUPVAL","SETTABLE","NEWTABLE",
	"SELF","ADD","SUB","MUL","DIV","MOD","POW","UNM","NOT","LEN","CONCAT",
	"JMP","EQ","LT","LE","TEST","TESTSET","CALL","TAILCALL","RETURN",
	"FORLOOP","FORPREP","TFORLOOP","SETLIST","CLOSE","CLOSURE","VARARG"
}

local ins = {}
for i, v in pairs(instructionNames) do ins[v] = i end

local iABC = 0
local iABx = 1
local iAsBx = 2

local instructionFormats = {
	[0]=iABC,iABx,iABC,iABC,
	iABC,iABx,iABC,
	iABx,iABC,iABC,iABC,
	iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,
	iAsBx,iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,
	iAsBx,iAsBx,iABC,iABC,iABC,iABx,iABC
}

--faster version of bytecode.encode, does not convert and do and checks
local function encode(ins,a,b,c)
	local fmt = instructionFormats[ins]
	if fmt == iABC then
		return ins+bit.blshift(a,6)+bit.blshift(c,14)+bit.blshift(b,23)
	elseif fmt == iABx then
		return ins+bit.blshift(a,6)+bit.blshift(b,14)
	elseif fmt == iAsBx then
		return ins+bit.blshift(a,6)+bit.blshift(b+131071,14)
	end
end
compiler.encode = encode

function compiler.compile(bcasm)
	local idx = 1
	
	local nconst = 0
	local constants = {}
	local ninstr = 0
	local instructions = {}
	
	local function matchSpace()
		local s, e = bcasm:find("^[ \n\t]*",idx)
		idx = e and e+1 or idx
		return not not e
	end
	
	local function matchComment()
		local s, e = bcasm:find("^%-%-(.-)\n",idx)
		idx = e and e+1 or idx
	end
	
	local function matchIdentifier()
		local s, e = bcasm:find("^([a-zA-Z_][a-zA-Z0-9_]*)",idx)
		idx = e and e+1 or idx
		return s and bcasm:sub(s,e) or nil
	end
	
	local function matchString()
		local b = bcasm:sub(idx,idx)
		if b == "'" or b == '"' then
			local sidx= idx
			idx = idx+1
			local c = bcasm:sub(idx,idx)
			local str = {}
			while c ~= b do
				if c == "\\" then
					local n = bcasm:sub(idx+1,idx+1)
					if n == "n" then
						str[#str+1] = "\n"
					elseif n == "t" then
						str[#str+1] = "\t"
					else
						str[#str+1] = n
					end
					idx = idx+1
				else
					str[#str+1] = c
				end
				idx = idx+1
				if idx > #bcasm then
					error("End of string not found at"..sidx,0)
				end
				c = bcasm:sub(idx,idx)
			end
			idx = idx+1
			return table.concat(str)
		end
	end
	
	local function matchNumber()
		local s, e = bcasm:find("^[-+]?%d+",idx)
		idx = e and e+1 or idx
		return s and tonumber(bcasm:sub(s,e)) or nil
	end
	
	local function matchValue()
		return matchNumber() or matchString()
	end
	
	local function matchConst()
		if bcasm:sub(idx,idx+5) == ".const" then
			local sidx = idx
			idx = idx+6
			matchSpace()
			local id = matchIdentifier()
			if not id then error("Failed to identify constant at "..sidx) end
			matchSpace()
			local val = matchValue()
			if not val then error("Failed to identify constant at "..sidx) end
			constants[nconst] = {name=id, value=val, idx=nconst}
			constants[id] = constants[nconst]
			nconst = nconst+1
		end
	end
	
	local function matchInstruction()
		local s,e = bcasm:find("^([^ \n\t]+)",idx)
		if not s then return end
		local iname = bcasm:sub(s,e):upper()
		local i = ins[iname]
		if not i then error("Invalid instruction name \""..iname.."\" at "..idx) end
		idx = e+1
		debug("Found instruction "..iname)
		local fmt = instructionFormats[i]
		local args = {}
		while #args < 2 or bcasm:sub(idx,idx) == "," do
			matchSpace()
			if bcasm:sub(idx,idx) == "," then idx = idx+1 matchSpace() end
			local id = matchIdentifier()
			if id then
				args[#args+1] = constants[id].idx
			else
				local num = matchNumber()
				if not num then
					error("Failed to identify constant at "..idx)
				end
				args[#args+1] = num
			end
		end
		
		instructions[ninstr] = encode(i,args[1] or 0,args[2] or 0,args[3] or 0)
		ninstr = ninstr+1
	end
	
	local lastidx = idx
	while idx < #bcasm do
		matchSpace()
		matchComment()
		matchSpace()
		matchConst()
		matchInstruction()
		if idx == lastidx then error("Failed to identify at "..idx) end
		lastidx = idx
	end
	
	local bc = bytecode.new()
	for i=0, nconst-1 do
		bc.constants[i] = constants[i].value
	end
	for i=0, ninstr-1 do
		bc.instructions[i] = instructions[i]
	end
	bc.instructions[ninstr] = bytecode.defaultReturn
	bc.maxStack = 127 --TODO: Max stack!
	return bc
end
