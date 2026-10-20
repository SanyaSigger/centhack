local httpService = game:GetService('HttpService')

-- Only fonts that exist on Enum.Font. Built by probing each name with pcall
-- so missing members (SourceSansBoldItalic, World, GothamSemibold, …) never crash.
local FONT_CANDIDATES = {
	'Legacy', 'Arial', 'ArialBold',
	'SourceSans', 'SourceSansBold', 'SourceSansLight', 'SourceSansItalic', 'SourceSansSemibold',
	'Bodoni', 'Garamond', 'Cartoon', 'Code', 'Highway', 'SciFi', 'Arcade', 'Fantasy', 'Antique',
	'Gotham', 'GothamMedium', 'GothamBold', 'GothamBlack',
	'AmaticSC', 'Bangers', 'Creepster', 'DenkOne', 'Fondamento', 'FredokaOne', 'GrenzeGotisch',
	'IndieFlower', 'JosefinSans', 'Jura', 'Kalam', 'LuckiestGuy', 'Merriweather', 'Michroma',
	'Nunito', 'Oswald', 'PatrickHand', 'PermanentMarker', 'Roboto', 'RobotoCondensed', 'RobotoMono',
	'Sarpanch', 'SpecialElite', 'TitilliumWeb', 'Ubuntu',
	'BuilderSans', 'BuilderSansMedium', 'BuilderSansBold', 'BuilderSansExtraBold',
	'Arimo', 'ArimoBold',
}

local function ResolveFont(name)
	if type(name) ~= 'string' or name == '' then
		return Enum.Font.Code
	end

	local ok, font = pcall(function()
		return Enum.Font[name]
	end)

	if ok and font ~= nil then
		return font
	end

	return Enum.Font.Code
end

local function GetAvailableFontNames()
	local names = {}

	for _, name in ipairs(FONT_CANDIDATES) do
		local ok, font = pcall(function()
			return Enum.Font[name]
		end)

		if ok and font ~= nil then
			table.insert(names, name)
		end
	end

	-- Fallback so the dropdown is never empty on weird executors.
	if #names == 0 then
		table.insert(names, 'Code')
	end

	table.sort(names)
	return names
end

local ThemeManager = {} do
	ThemeManager.Folder = 'LinoriaLibSettings'
	-- if not isfolder(ThemeManager.Folder) then makefolder(ThemeManager.Folder) end

	ThemeManager.Library = nil
	ThemeManager.FontNames = GetAvailableFontNames()
	ThemeManager.BuiltInThemes = {
		['Default'] 		= { 1, httpService:JSONDecode('{"FontColor":"ffffff","MainColor":"1c1c1c","AccentColor1":"0055ff","AccentColor2":"0055ff","UseGradient":false,"BackgroundColor":"141414","OutlineColor":"323232"}') },
		['BBot'] 			= { 2, httpService:JSONDecode('{"FontColor":"ffffff","MainColor":"1e1e1e","AccentColor1":"7e48a3","AccentColor2":"7e48a3","UseGradient":false,"BackgroundColor":"232323","OutlineColor":"141414"}') },
		['Fatality']		= { 3, httpService:JSONDecode('{"FontColor":"ffffff","MainColor":"1e1842","AccentColor1":"c50754","AccentColor2":"c50754","UseGradient":false,"BackgroundColor":"191335","OutlineColor":"3c355d"}') },
		['Jester'] 			= { 4, httpService:JSONDecode('{"FontColor":"ffffff","MainColor":"242424","AccentColor1":"db4467","AccentColor2":"db4467","UseGradient":false,"BackgroundColor":"1c1c1c","OutlineColor":"373737"}') },
		['Mint'] 			= { 5, httpService:JSONDecode('{"FontColor":"ffffff","MainColor":"242424","AccentColor1":"3db488","AccentColor2":"3db488","UseGradient":false,"BackgroundColor":"1c1c1c","OutlineColor":"373737"}') },
		['Tokyo Night'] 	= { 6, httpService:JSONDecode('{"FontColor":"ffffff","MainColor":"191925","AccentColor1":"6759b3","AccentColor2":"6759b3","UseGradient":false,"BackgroundColor":"16161f","OutlineColor":"323232"}') },
		['Ubuntu'] 			= { 7, httpService:JSONDecode('{"FontColor":"ffffff","MainColor":"3e3e3e","AccentColor1":"e2581e","AccentColor2":"e2581e","UseGradient":false,"BackgroundColor":"323232","OutlineColor":"191919"}') },
		['Quartz'] 			= { 8, httpService:JSONDecode('{"FontColor":"ffffff","MainColor":"232330","AccentColor1":"426e87","AccentColor2":"426e87","UseGradient":false,"BackgroundColor":"1d1b26","OutlineColor":"27232f"}') },
	}

	function ThemeManager:ApplyTheme(theme)
		local customThemeData = self:GetCustomTheme(theme)
		local data = customThemeData or self.BuiltInThemes[theme]

		if not data then return end

		-- custom themes are just regular dictionaries instead of an array with { index, dictionary }

		local scheme = data[2]
		local colorFields = {
			FontColor = true;
			MainColor = true;
			AccentColor1 = true;
			AccentColor2 = true;
			BackgroundColor = true;
			OutlineColor = true;
		}

		for idx, col in next, customThemeData or scheme do
			if colorFields[idx] then
				local color = self.Library:ColorFromHex(col)
				self.Library[idx] = color
				
				if Options[idx] then
					Options[idx]:SetValueRGB(color)
				end
			elseif idx == 'UseGradient' then
				if Options.ThemeManager_UseGradient then
					Options.ThemeManager_UseGradient:SetValue(col == true or col == 'true')
				end
			elseif idx == 'FontName' then
				if Options.ThemeManager_FontName then
					Options.ThemeManager_FontName:SetValue(col)
				end
			elseif idx == 'FontSize' then
				if Options.ThemeManager_FontSize then
					Options.ThemeManager_FontSize:SetValue(tonumber(col) or 14)
				end
			elseif idx == 'BackgroundImage' then
				if Options.ThemeManager_BackgroundImage then
					Options.ThemeManager_BackgroundImage:SetValue(tostring(col))
				end
			elseif idx == 'BackgroundImageTransparency' then
				if Options.ThemeManager_BackgroundImageTransparency then
					Options.ThemeManager_BackgroundImageTransparency:SetValue((tonumber(col) or 0) * 100)
				end
			elseif idx == 'BackgroundBlur' then
				if Options.ThemeManager_BackgroundBlur then
					Options.ThemeManager_BackgroundBlur:SetValue((tonumber(col) or 0) / 24 * 100)
				end
			end
		end

		self:ThemeUpdate()
	end

	function ThemeManager:ThemeUpdate()
		-- This allows us to force apply themes without loading the themes tab :)
		local fieldMap = {
			FontColor = 'FontColor';
			MainColor = 'MainColor';
			AccentColor1 = 'AccentColor1';
			AccentColor2 = 'AccentColor2';
			ThemeManager_UseGradient = 'UseGradient';
			BackgroundColor = 'BackgroundColor';
			OutlineColor = 'OutlineColor';
			ThemeManager_FontName = 'FontName';
			ThemeManager_FontSize = 'FontSize';
			ThemeManager_BackgroundImage = 'BackgroundImage';
			ThemeManager_BackgroundImageTransparency = 'BackgroundImageTransparency';
			ThemeManager_BackgroundBlur = 'BackgroundBlur';
		}
		for optionName, libField in next, fieldMap do
			if Options and Options[optionName] then
				local val = Options[optionName].Value
				-- Sliders use 0-100, the library stores 0-1 for transparency / 0-24 for blur
				if libField == 'BackgroundImageTransparency' then
					val = (tonumber(val) or 0) / 100
				elseif libField == 'BackgroundBlur' then
					val = (tonumber(val) or 0) / 100 * 24
				end
				-- Convert font name string to Enum.Font (safely — invalid names fall back to Code)
				if libField == 'FontName' then
					self.Library.Font = ResolveFont(val)
					self.Library.FontName = (type(val) == 'string' and val ~= '') and val or (self.Library.FontName or 'Code')
				end
				self.Library[libField] = val;
			end
		end

		self.Library.AccentColorDark = self.Library:GetDarkerColor(self.Library.AccentColor1);
		self.Library:UpdateColorsUsingRegistry()
	end

	function ThemeManager:LoadDefault()		
		local theme = 'Default'
		local content = isfile(self.Folder .. '/themes/default.txt') and readfile(self.Folder .. '/themes/default.txt')

		local isDefault = true
		if content then
			if self.BuiltInThemes[content] then
				theme = content
			elseif self:GetCustomTheme(content) then
				theme = content
				isDefault = false;
			end
		elseif self.BuiltInThemes[self.DefaultTheme] then
		 	theme = self.DefaultTheme
		end

		if isDefault then
			Options.ThemeManager_ThemeList:SetValue(theme)
		else
			self:ApplyTheme(theme)
		end
	end

	function ThemeManager:SaveDefault(theme)
		writefile(self.Folder .. '/themes/default.txt', theme)
	end

	function ThemeManager:CreateThemeManager(groupbox)
		groupbox:AddLabel('Background color'):AddColorPicker('BackgroundColor', { Default = self.Library.BackgroundColor });
		groupbox:AddLabel('Main color')	:AddColorPicker('MainColor', { Default = self.Library.MainColor });
		groupbox:AddLabel('Accent color 1'):AddColorPicker('AccentColor1', { Default = self.Library.AccentColor1 });
		groupbox:AddLabel('Accent color 2'):AddColorPicker('AccentColor2', { Default = self.Library.AccentColor2 });
		groupbox:AddToggle('ThemeManager_UseGradient', {
			Text = 'Use accent gradient';
			Default = not self.Library:ColorsEqual(self.Library.AccentColor1, self.Library.AccentColor2);
		});
		groupbox:AddLabel('Outline color'):AddColorPicker('OutlineColor', { Default = self.Library.OutlineColor });
		groupbox:AddLabel('Font color')	:AddColorPicker('FontColor', { Default = self.Library.FontColor });



		groupbox:AddDivider()

		groupbox:AddLabel('Font name')
		groupbox:AddDropdown('ThemeManager_FontName', {
			Text = 'Font';
			Values = self.FontNames;
			Default = self.Library.FontName or 'Code';
		});

		groupbox:AddSlider('ThemeManager_FontSize', {
			Text = 'Font size';
			Default = self.Library.FontSize;
			Min = 8;
			Max = 32;
			Rounding = 0;
		});

		groupbox:AddDivider()

		groupbox:AddLabel('Background image')
		groupbox:AddInput('ThemeManager_BackgroundImage', {
			Text = 'Image ID (rbxassetid://...)';
			Default = self.Library.BackgroundImage;
		});

		groupbox:AddSlider('ThemeManager_BackgroundImageTransparency', {
			Text = 'Image transparency';
			Default = self.Library.BackgroundImageTransparency * 100;
			Min = 0;
			Max = 100;
			Rounding = 0;
		});

		groupbox:AddSlider('ThemeManager_BackgroundBlur', {
			Text = 'Blur (%)';
			Default = (self.Library.BackgroundBlur or 0) / 24 * 100;
			Min = 0;
			Max = 100;
			Rounding = 0;
		});
		local ThemesArray = {}
		for Name, Theme in next, self.BuiltInThemes do
			table.insert(ThemesArray, Name)
		end

		table.sort(ThemesArray, function(a, b) return self.BuiltInThemes[a][1] < self.BuiltInThemes[b][1] end)

		groupbox:AddDivider()
		groupbox:AddDropdown('ThemeManager_ThemeList', { Text = 'Theme list', Values = ThemesArray, Default = 1 })

		groupbox:AddButton('Set as default', function()
			self:SaveDefault(Options.ThemeManager_ThemeList.Value)
			self.Library:Notify(string.format('Set default theme to %q', Options.ThemeManager_ThemeList.Value))
		end)

		Options.ThemeManager_ThemeList:OnChanged(function()
			self:ApplyTheme(Options.ThemeManager_ThemeList.Value)
		end)

		groupbox:AddDivider()
		groupbox:AddInput('ThemeManager_CustomThemeName', { Text = 'Custom theme name' })
		groupbox:AddDropdown('ThemeManager_CustomThemeList', { Text = 'Custom themes', Values = self:ReloadCustomThemes(), AllowNull = true, Default = 1 })
		groupbox:AddDivider()
		
		groupbox:AddButton('Save theme', function() 
			self:SaveCustomTheme(Options.ThemeManager_CustomThemeName.Value)

			Options.ThemeManager_CustomThemeList:SetValues(self:ReloadCustomThemes())
			Options.ThemeManager_CustomThemeList:SetValue(nil)
		end):AddButton('Load theme', function() 
			self:ApplyTheme(Options.ThemeManager_CustomThemeList.Value) 
		end)

		groupbox:AddButton('Refresh list', function()
			Options.ThemeManager_CustomThemeList:SetValues(self:ReloadCustomThemes())
			Options.ThemeManager_CustomThemeList:SetValue(nil)
		end)

		groupbox:AddButton('Set as default', function()
			if Options.ThemeManager_CustomThemeList.Value ~= nil and Options.ThemeManager_CustomThemeList.Value ~= '' then
				self:SaveDefault(Options.ThemeManager_CustomThemeList.Value)
				self.Library:Notify(string.format('Set default theme to %q', Options.ThemeManager_CustomThemeList.Value))
			end
		end)

		ThemeManager:LoadDefault()

		local function UpdateTheme()
			self:ThemeUpdate()
		end

		Options.BackgroundColor:OnChanged(UpdateTheme)
		Options.MainColor:OnChanged(UpdateTheme)
		Options.AccentColor1:OnChanged(UpdateTheme)
		Options.AccentColor2:OnChanged(UpdateTheme)
		Options.ThemeManager_UseGradient:OnChanged(UpdateTheme)
		Options.OutlineColor:OnChanged(UpdateTheme)
		Options.FontColor:OnChanged(UpdateTheme)
		Options.ThemeManager_FontName:OnChanged(UpdateTheme)
		Options.ThemeManager_FontSize:OnChanged(UpdateTheme)
		Options.ThemeManager_BackgroundImage:OnChanged(UpdateTheme)
		Options.ThemeManager_BackgroundImageTransparency:OnChanged(UpdateTheme)
		Options.ThemeManager_BackgroundBlur:OnChanged(UpdateTheme)
	end

	function ThemeManager:GetCustomTheme(file)
		local path = self.Folder .. '/themes/' .. file
		if not isfile(path) then
			return nil
		end

		local data = readfile(path)
		local success, decoded = pcall(httpService.JSONDecode, httpService, data)
		
		if not success then
			return nil
		end

		return decoded
	end

	function ThemeManager:SaveCustomTheme(file)
		if file:gsub(' ', '') == '' then
			return self.Library:Notify('Invalid file name for theme (empty)', 3)
		end

		local theme = {}
		local fields = { "FontColor", "MainColor", "AccentColor1", "AccentColor2", "BackgroundColor", "OutlineColor" }

		for _, field in next, fields do
			if Options[field] then
				theme[field] = self.Library:ColorToHex(Options[field].Value)
			end
		end

		if Options.ThemeManager_UseGradient then
			theme.UseGradient = Options.ThemeManager_UseGradient.Value and true or false
		end

		-- Font settings (stored as string names)
		if Options.ThemeManager_FontName then
			theme.FontName = Options.ThemeManager_FontName.Value
		end
		if Options.ThemeManager_FontSize then
			theme.FontSize = Options.ThemeManager_FontSize.Value
		end

		-- Background image settings
		if Options.ThemeManager_BackgroundImage then
			theme.BackgroundImage = Options.ThemeManager_BackgroundImage.Value
		end
		-- Stored in the library scale (0-1 transparency, 0-24 blur) so themes
		-- round-trip through ApplyTheme without any extra conversion.
		if Options.ThemeManager_BackgroundImageTransparency then
			theme.BackgroundImageTransparency = (tonumber(Options.ThemeManager_BackgroundImageTransparency.Value) or 0) / 100
		end
		if Options.ThemeManager_BackgroundBlur then
			theme.BackgroundBlur = (tonumber(Options.ThemeManager_BackgroundBlur.Value) or 0) / 100 * 24
		end

		writefile(self.Folder .. '/themes/' .. file .. '.json', httpService:JSONEncode(theme))
	end

	function ThemeManager:ReloadCustomThemes()
		local list = listfiles(self.Folder .. '/themes')

		local out = {}
		for i = 1, #list do
			local file = list[i]
			if file:sub(-5) == '.json' then
				-- i hate this but it has to be done ...

				local pos = file:find('.json', 1, true)
				local char = file:sub(pos, pos)

				while char ~= '/' and char ~= '\\' and char ~= '' do
					pos = pos - 1
					char = file:sub(pos, pos)
				end

				if char == '/' or char == '\\' then
					table.insert(out, file:sub(pos + 1))
				end
			end
		end

		return out
	end

	function ThemeManager:SetLibrary(lib)
		self.Library = lib
	end

	function ThemeManager:BuildFolderTree()
		local paths = {}

		-- build the entire tree if a path is like some-hub/phantom-forces
		-- makefolder builds the entire tree on Synapse X but not other exploits

		local parts = self.Folder:split('/')
		for idx = 1, #parts do
			paths[#paths + 1] = table.concat(parts, '/', 1, idx)
		end

		table.insert(paths, self.Folder .. '/themes')
		table.insert(paths, self.Folder .. '/settings')

		for i = 1, #paths do
			local str = paths[i]
			if not isfolder(str) then
				makefolder(str)
			end
		end
	end

	function ThemeManager:SetFolder(folder)
		self.Folder = folder
		self:BuildFolderTree()
	end

	function ThemeManager:CreateGroupBox(tab)
		assert(self.Library, 'Must set ThemeManager.Library first!')
		return tab:AddLeftGroupbox('Themes')
	end

	function ThemeManager:ApplyToTab(tab)
		assert(self.Library, 'Must set ThemeManager.Library first!')
		local groupbox = self:CreateGroupBox(tab)
		self:CreateThemeManager(groupbox)
	end

	function ThemeManager:ApplyToGroupbox(groupbox)
		assert(self.Library, 'Must set ThemeManager.Library first!')
		self:CreateThemeManager(groupbox)
	end

	ThemeManager:BuildFolderTree()
end

return ThemeManager