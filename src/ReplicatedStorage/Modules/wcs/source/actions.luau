-- Compiled with roblox-ts v3.0.0
local TS = require(script.Parent.Parent.include.RuntimeLib)
local notify = TS.import(script, script.Parent.Parent, "include", "node_modules", "@rbxts", "charm").notify
local produce = TS.import(script, script.Parent.Parent, "include", "node_modules", "@rbxts", "immut", "src").produce
local _utility = TS.import(script, script.Parent, "utility")
local getActiveHandler = _utility.getActiveHandler
local logError = _utility.logError
local function MutateAtom(atom, recipe)
	atom(produce(atom(), recipe))
	notify(atom)
end
local function getAtom()
	local handler = getActiveHandler()
	if not handler then
		logError("Attempted to dispatch an action before server handler initialization.")
	end
	return handler._internal_atom
end
local function setCharacterData(CharacterIndex, CharacterData)
	MutateAtom(getAtom(), function(Draft)
		local _draft = Draft
		local _characterIndex = CharacterIndex
		local _characterData = CharacterData
		_draft[_characterIndex] = _characterData
	end)
end
local function patchCharacterData(CharacterIndex, Patch)
	local atom = getAtom()
	local state = atom()
	local _characterIndex = CharacterIndex
	local currentData = state[_characterIndex]
	if not currentData then
		return nil
	end
	local _object = table.clone(currentData)
	setmetatable(_object, nil)
	for _k, _v in Patch do
		_object[_k] = _v
	end
	local patchedData = _object
	MutateAtom(atom, function(Draft)
		local _draft = Draft
		local _characterIndex_1 = CharacterIndex
		_draft[_characterIndex_1] = patchedData
	end)
end
local function deleteCharacterData(CharacterIndex)
	MutateAtom(getAtom(), function(Draft)
		local _draft = Draft
		local _characterIndex = CharacterIndex
		_draft[_characterIndex] = nil
	end)
end
local function setStatusData(CharacterIndex, Id, Data)
	MutateAtom(getAtom(), function(Draft)
		local _draft = Draft
		local _characterIndex = CharacterIndex
		local _statusEffects = _draft[_characterIndex]
		if _statusEffects ~= nil then
			_statusEffects = _statusEffects.statusEffects
		end
		local statusEffects = _statusEffects
		local _result = statusEffects
		if _result ~= nil then
			local _id = Id
			local _data = Data
			_result[_id] = _data
		end
	end)
end
local function deleteStatusData(CharacterIndex, Id)
	MutateAtom(getAtom(), function(Draft)
		local _draft = Draft
		local _characterIndex = CharacterIndex
		local _statusEffects = _draft[_characterIndex]
		if _statusEffects ~= nil then
			_statusEffects = _statusEffects.statusEffects
		end
		local statusEffects = _statusEffects
		local _result = statusEffects
		if _result ~= nil then
			local _id = Id
			_result[_id] = nil
		end
	end)
end
local function patchStatusData(CharacterIndex, Id, Patch)
	local atom = getAtom()
	local state = atom()
	local _characterIndex = CharacterIndex
	local characterData = state[_characterIndex]
	if not characterData then
		return state
	end
	local _statusEffects = characterData.statusEffects
	local _id = Id
	local previous = _statusEffects[_id]
	if not previous then
		return state
	end
	local _object = table.clone(previous)
	setmetatable(_object, nil)
	for _k, _v in Patch do
		_object[_k] = _v
	end
	local patchedData = _object
	MutateAtom(atom, function(Draft)
		local _draft = Draft
		local _characterIndex_1 = CharacterIndex
		local _statusEffects_1 = _draft[_characterIndex_1]
		if _statusEffects_1 ~= nil then
			_statusEffects_1 = _statusEffects_1.statusEffects
		end
		local statusEffects = _statusEffects_1
		local _result = statusEffects
		if _result ~= nil then
			local _id_1 = Id
			_result[_id_1] = patchedData
		end
	end)
end
local function setSkillData(CharacterIndex, Name, Data)
	MutateAtom(getAtom(), function(Draft)
		local _draft = Draft
		local _characterIndex = CharacterIndex
		local _skills = _draft[_characterIndex]
		if _skills ~= nil then
			_skills = _skills.skills
		end
		local skills = _skills
		local _result = skills
		if _result ~= nil then
			local _name = Name
			local _data = Data
			_result[_name] = _data
		end
	end)
end
local function deleteSkillData(CharacterIndex, Name)
	MutateAtom(getAtom(), function(Draft)
		local _draft = Draft
		local _characterIndex = CharacterIndex
		local _skills = _draft[_characterIndex]
		if _skills ~= nil then
			_skills = _skills.skills
		end
		local skills = _skills
		local _result = skills
		if _result ~= nil then
			local _name = Name
			_result[_name] = nil
		end
	end)
end
local function patchSkillData(CharacterIndex, Name, Patch)
	local atom = getAtom()
	local state = atom()
	local _characterIndex = CharacterIndex
	local characterData = state[_characterIndex]
	if not characterData then
		return nil
	end
	local _skills = characterData.skills
	local _name = Name
	local previous = _skills[_name]
	if not previous then
		return nil
	end
	local _object = table.clone(previous)
	setmetatable(_object, nil)
	for _k, _v in Patch do
		_object[_k] = _v
	end
	local patchedData = _object
	MutateAtom(atom, function(Draft)
		local _draft = Draft
		local _characterIndex_1 = CharacterIndex
		local _skills_1 = _draft[_characterIndex_1]
		if _skills_1 ~= nil then
			_skills_1 = _skills_1.skills
		end
		local skills = _skills_1
		local _result = skills
		if _result ~= nil then
			local _name_1 = Name
			_result[_name_1] = patchedData
		end
	end)
end
return {
	setCharacterData = setCharacterData,
	patchCharacterData = patchCharacterData,
	deleteCharacterData = deleteCharacterData,
	setStatusData = setStatusData,
	deleteStatusData = deleteStatusData,
	patchStatusData = patchStatusData,
	setSkillData = setSkillData,
	deleteSkillData = deleteSkillData,
	patchSkillData = patchSkillData,
}
