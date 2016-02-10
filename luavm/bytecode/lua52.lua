return function(bytecode)
	local impl = {}
	
	local debug = bytecode.printDebug
	local bit = bytecode.bit
	
	-- instruction definitions
	
	local instructionNames = {
		[0]="MOVE","LOADK","LOADKX","LOADBOOL","LOADNIL",
		"GETUPVAL","GETTABUP","GETTABLE",
		"SETTABUP","SETUPVAL","SETTABLE","NEWTABLE",
		"SELF","ADD","SUB","MUL","DIV","MOD","POW","UNM","NOT","LEN","CONCAT",
		"JMP","EQ","LT","LE","TEST","TESTSET","CALL","TAILCALL","RETURN",
		"FORLOOP","FORPREP","TFORCALL","TFORLOOP","SETLIST","CLOSURE","VARARG","EXTRAARG"
	}

	local iABC = 0
	local iABx = 1
	local iAsBx = 2
	local iA = 3
	local iAx = 4

	local instructionFormats = {
		[0]=iABC,iABx,iA,iABC,iABC,
		iABC,iABC,iABC,
		iABC,iABC,iABC,iABC,
		iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,
		iAsBx,iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,
		iAsBx,iAsBx,iABC,iAsBx,iABC,iABx,iABC,iAx
	}
	
	local ins = {}
	for i, v in pairs(instructionNames) do ins[v] = i end
	
	impl.instructionNames = instructionNames
	impl.instructions = ins
	impl.defaultReturn = 8388638

	-- instruction constants
	
	local MOVE = 0
	local LOADK = 1
	local LOADKX = 2
	local LOADBOOL = 3
	local LOADNIL = 4
	local GETUPVAL = 5
	local GETTABUP = 6
	local GETTABLE = 7
	local SETTABUP = 8
	local SETUPVAL = 9
	local SETTABLE = 10
	local NEWTABLE = 11
	local SELF = 12
	local ADD = 13
	local SUB = 14
	local MUL = 15
	local DIV = 16
	local MOD = 17
	local POW = 18
	local UNM = 19
	local NOT = 20
	local LEN = 21
	local CONCAT = 22
	local JMP = 23
	local EQ = 24
	local LT = 25
	local LE = 26
	local TEST = 27
	local TESTSET = 28
	local CALL = 29
	local TAILCALL = 30
	local RETURN = 31
	local FORLOOP = 32
	local FORPREP = 33
	local TFORCALL = 34
	local TFORLOOP = 35
	local SETLIST = 36
	local CLOSURE = 37
	local VARARG = 38
	local EXTRAARG = 39
	
	-- instruction encoding and decoding

	function impl.encode(inst,a,b,c)
		inst = type(inst) == "string" and ins[inst] or inst
		local format = instructionFormats[inst]
		return
			format == iABC and
			bit.bor(inst,bit.blshift(bit.band(a,0xFF),6),bit.blshift(bit.band(b,0x1FF),23), bit.blshift(bit.band(c,0x1FF),14)) or
			format == iABx and
			bit.bor(inst,bit.blshift(bit.band(a,0xFF),6),bit.blshift(bit.band(b,0x3FFFF),14)) or
			bit.bor(inst,bit.blshift(bit.band(a,0xFF),6),bit.blshift(bit.band(b+131071,0x3FFFF),14))
	end

	function impl.decode(inst)
		local opcode = bit.band(inst,0x3F)
		local format = instructionFormats[opcode]
		if format == iABC then
			return opcode, bit.band(bit.brshift(inst,6),0xFF), bit.band(bit.brshift(inst,23),0x1FF), bit.band(bit.brshift(inst,14),0x1FF)
		elseif format == iABx then
			return opcode, bit.band(bit.brshift(inst,6),0xFF), bit.band(bit.brshift(inst,14),0x3FFFF)
		elseif format == iAsBx then
			local sBx = bit.band(bit.brshift(inst,14),0x3FFFF)-131071
			return opcode, bit.band(bit.brshift(inst,6),0xFF), sBx
		else
			error(opcode.." "..format)
		end
	end
	
	-- bytecode loading
	
	function impl.loadHeader(bc)
		local header = {version = 0x52}
		
		local fmtver = bc:byte(6)
		header.fmtver = fmtver
		debug("Format Version: %02X", fmtver)
		
		local types = bc:sub(7, 12)
		debug("Types: "..types:gsub(".", function(c) return string.format("%02X ", c:byte()) end))
		
		local bigEndian = types:byte(1) ~= 1
		header.bigEndian = bigEndian
		debug("Big Endian: %s", tostring(bigEndian))
		
		local integer = types:byte(2)
		header.integer = integer
		debug("Integer Size: %d bytes", integer)
		
		local size_t = types:byte(3)
		header.size_t = size_t
		debug("Size_T Size: %d bytes", size_t)
		
		local instruction = types:byte(4)
		header.instruction = instruction
		debug("Instruction Size: %d bytes", instruction)
		
		--integral or numerical number stuff
		do
			local integralNumbers = types:byte(6) ~= 0
			local size = types:byte(5)
			header.number_integral = integralNumbers
			header.number = size
			debug("Numerical Format: %d bytes <%s>", size, integralNumbers and "integral" or "floating")
		end
		
		return header
	end
	
	function impl.load(bc)
		debug("Lua 5.2 Bytecode Loader")
		
		local idx = 13
		local integer, size_t, number
		local bigEndian
		local binarytypes = bytecode.binarytypes
		
		local function u1()
			idx = idx+1
			return binarytypes.decode.u1(bc, idx-1, bigEndian)
		end
		
		local function u2()
			idx = idx+2
			return binarytypes.decode.u2(bc, idx-2, bigEndian)
		end
		
		local function u4()
			idx = idx+4
			return binarytypes.decode.u4(bc, idx-4, bigEndian)
		end
		
		local function u8()
			idx = idx+8
			return binarytypes.decode.u8(bc, idx-8, bigEndian)
		end
		
		local function float()
			idx = idx+4
			return binarytypes.decode.float(bc, idx-4, bigEndian)
		end
		
		local function double()
			idx = idx+8
			return binarytypes.decode.double(bc, idx-8, bigEndian)
		end
		
		local function ub(n)
			idx = idx+n
			return bc:sub(idx-n,idx-1)
		end
		
		local function us()
			local size = size_t()
			--print(size)
			return ub(size):sub(1,-2)
		end
		
		local integralSizes = {
			[1] = u1,
			[2] = u2,
			[4] = u4,
			[8] = u8
		}
		
		local numericSizes = {
			[4] = float,
			[8] = double
		}
		
		local header = impl.loadHeader(bc)
		
		assert(header.fmtver == 0 or header.fmtver == 255, "unknown format version: "..header.fmtver)
		bigEndian = header.bigEndian
		integer = assert(integralSizes[header.integer], "unsupported integer size: "..header.integer)
		size_t = assert(integralSizes[header.size_t], "unsupported size_t size: "..header.size_t)
		assert(header.instruction == 4, "unsupported instruction size: "..header.instruction)
		
		--integral or numerical number stuff
		do
			local integralNumbers = header.number_integral
			local size = header.number
			number = assert(integralNumbers and integralSizes[size] or numericSizes[size], "unsupported number size: "..(integralNumbers and "integral" or "floating").." "..size)
		end
		
		assert(ub(6) == "\25\147\r\n\26\n", "header has invalid tail")
		
		local function chunk()
			local function instructionList()
				local instructions = {}
				local count = integer()
				for i=1, count do
					instructions[i-1] = u4()
				end
				return instructions
			end
			
			local function constantList()
				local constants = {}
				local c = integer()
				for i=1, c do
					local type = u1()
					if type == 0 then
						constants[i-1] = nil
					elseif type == 1 then
						constants[i-1] = u1() > 0
					elseif type == 3 then
						constants[i-1] = number()
					elseif type == 4 then
						constants[i-1] = us()
					else
						error("Type: "..type)
					end
					debug("Constant %d: %s %s", i-1, tostring(constants[i-1]), type)
				end
				return constants
			end
			
			local function functionPrototypeList()
				local functionPrototypes = {}
				for i=1, integer() do
					functionPrototypes[i-1] = chunk()
				end
				return functionPrototypes
			end
			
			local function sourceLineList()
				local sourceLines = {}
				for i=1, integer() do
					sourceLines[i-1] = integer()
				end
				return sourceLines
			end
			
			local function localList()
				local locals = {}
				for i=1, integer() do
					locals[i-1] = {
						name = us(),
						startpc = integer(),
						endpc = integer()
					}
				end
				return locals
			end
			
			local function upvalueList()
				local upvalues = {}
				for i=1, integer() do
					upvalues[i-1] = us()
				end
				return upvalues
			end
			
			local function upvalueDefinitionList()
				local upvalues = {}
				for i=1, integer() do
					upvalues[i-1] = {instack=u1(),idx=u1()}
					debug("upvalue %d instack=%d idx=%d", i-1, upvalues[i-1].instack, upvalues[i-1].idx)
				end
				return upvalues
			end
			
			--extract an lua chunk into a table--
			local c = {header = header}
			
			c.lineDefined = integer()
			c.lastLineDefined = integer()
			c.nparam = u1()
			c.isvararg = u1()
			c.maxStack = u1()
			c.instructions = instructionList()
			c.constants = constantList()
			c.functionPrototypes = functionPrototypeList()
			c.upvalues = upvalueDefinitionList()
			c.name = us()
			c.sourceLines = sourceLineList()
			c.locals = localList()
			c.upvaluesDebug = upvalueList()
			return c
		end
		
		return chunk()
	end
	
	return impl
end