local httpService = game:GetService('HttpService')

local SaveManager = {}
SaveManager.Folder = 'LinoriaLibSettings'
SaveManager.Ignore = {}

-- Serializes a value for JSON storage.
local function SerializeValue(object)
	local Type = object.Type;

	if Type == 'Toggle' then
		return object.Value == true;
	elseif Type == 'Slider' then
		return object.Value;
	elseif Type == 'Dropdown' then
		return object.Value;
	elseif Type == 'ColorPicker' then
		local Lib = getgenv().Library;
		return Lib and Lib:ColorToHex(object.Value) or object.Value:ToHex();
	elseif Type == 'KeyPicker' then
		return object.Value;
	elseif Type == 'Input' then
		return object.Value or '';
	end;

	return nil;
end

-- Deserializes a saved value back onto an object.
local function DeserializeValue(object, data)
	local Type = object.Type;

	if Type == 'Toggle' then
		if object.SetValue then
			object:SetValue(data == true);
		end
	elseif Type == 'Slider' then
		if object.SetValue and type(data) == 'number' then
			object:SetValue(data);
		end
	elseif Type == 'Dropdown' then
		if object.SetValue and type(data) == 'string' then
			object:SetValue(data);
		end
	elseif Type == 'ColorPicker' then
		if object.SetValueRGB then
			local Lib = getgenv().Library;
			local color = Lib and Lib:ColorFromHex(data) or Color3.fromHex(data);
			object:SetValueRGB(color, object.Transparency or 0);
		end
	elseif Type == 'KeyPicker' then
		if object.Value ~= nil then
			object.Value = data;
		end
	elseif Type == 'Input' then
		if object.SetValue and type(data) == 'string' then
			object:SetValue(data);
		end
	end
end

function SaveManager:SetIgnoreIndexes(list)
	for _, key in next, list do
		self.Ignore[key] = true;
	end
end

function SaveManager:SetFolder(folder)
	self.Folder = folder;
	self:BuildFolderTree()
end

function SaveManager:SetLibrary(library)
	self.Library = library;
end

function SaveManager:Save(name)
	if (not name) then
		return false, 'no config file is selected';
	end

	local fullPath = self.Folder .. '/settings/' .. name .. '.json';
	local encoded = self:EncodeConfig();

	writefile(fullPath, encoded);
	return true;
end

function SaveManager:EncodeConfig()
	local out = {};

	for idx, toggle in next, Toggles do
		if not self.Ignore[idx] then
			local val = SerializeValue(toggle);
			if val ~= nil then
				out[idx] = val;
			end
		end
	end

	for idx, option in next, Options do
		if not self.Ignore[idx] then
			local val = SerializeValue(option);
			if val ~= nil then
				out[idx] = val;
			end
		end
	end

	return httpService:JSONEncode(out);
end

function SaveManager:DecodeConfig(text)
	if type(text) ~= 'string' then
		return false, 'invalid config format';
	end

	local success, data = pcall(httpService.JSONDecode, httpService, text);
	if not success or type(data) ~= 'table' then
		return false, 'invalid config format';
	end

	for idx, val in next, data do
		local object = Toggles[idx] or Options[idx];
		if object then
			DeserializeValue(object, val);
		end
	end

	Library:AttemptSave();
	return true;
end

function SaveManager:ExportConfig()
	return self:EncodeConfig();
end

function SaveManager:ImportConfig(text)
	local success, err = self:DecodeConfig(text);
	if not success then
		return false, err;
	end
	return true;
end

function SaveManager:Load(name)
	if (not name) then
		return false, 'no config file is selected';
	end

	local file = self.Folder .. '/settings/' .. name .. '.json';
	if not isfile(file) then return false, 'invalid file' end

	local content = readfile(file);
	return self:DecodeConfig(content);
end

function SaveManager:IgnoreThemeSettings()
	self:SetIgnoreIndexes({
		"BackgroundColor", "MainColor", "AccentColor1", "AccentColor2", "OutlineColor", "FontColor", -- themes
		"ThemeManager_UseGradient", -- themes
		"ThemeManager_FontName", "ThemeManager_FontSize", -- typography
		"ThemeManager_BackgroundImage", "ThemeManager_BackgroundImageTransparency", "ThemeManager_BackgroundBlur", -- background
		"ThemeManager_ThemeList", 'ThemeManager_CustomThemeList', 'ThemeManager_CustomThemeName', -- themes
	})
end

function SaveManager:BuildFolderTree()
	local paths = {
		self.Folder,
		self.Folder .. '/themes',
		self.Folder .. '/settings'
	};

	for i = 1, #paths do
		local str = paths[i];

		if not isfolder(str) then
			makefolder(str);
		end
	end
end

function SaveManager:RefreshConfigList()
	local list = listfiles(self.Folder .. '/settings');

	local out = {};
	for i = 1, #list do
		local file = list[i];
		if file:sub(-5) == '.json' then
			local pos = file:find('.json', 1, true);
			local char = file:sub(pos, pos);

			while char ~= '/' and char ~= '\\' and char ~= '' do
				pos = pos - 1;
				char = file:sub(pos, pos);
			end

			if char == '/' or char == '\\' then
				table.insert(out, file:sub(pos + 1));
			end
		end
	end

	return out;
end

function SaveManager:LoadAutoloadConfig()
	if isfile(self.Folder .. '/settings/autoload.txt') then
		local name = readfile(self.Folder .. '/settings/autoload.txt');

		local success, err = self:Load(name);

		if not success then
			return self.Library:Notify('Failed to load autoload config: ' .. err);
		end

		self.Library:Notify(string.format('Auto loaded config %q', name));
	end
end

return SaveManager
