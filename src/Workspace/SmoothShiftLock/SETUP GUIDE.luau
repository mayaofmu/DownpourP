--[[

	-<< SmoothShiftLock Setup Guide >>-
	
	1. Put "DisableDefaultShiftLock" script into ServerScriptService.
		(Alternatively click on StarterPlayer and in properties under Controls find EnableMouseLockOption and uncheck the box)
	2. Put "CustomShiftLock" script into StarterPlayer>StarterPlayerScripts.

	Congratulations, you've successfully set up SmoothShiftLock!
	The settings of SmoothShiftLock are located at CustomShiftLock>SmoothShiftLock (Line 31)
	
	
	
	
	-<< For Advanced Scripters >>-
	
	To access the module's methods, simply require the SmoothShiftLock module script.
	Example:
	
	```
	local SmoothShiftLock = require(CustomShiftLock.SmoothShiftLock);
	print(SmoothShiftLock:IsEnabled());
	```
	
	@ Variables:
	└	.Enabled - ShiftLock's enabled state.
		
	@ Methods:
	│	:Enable() - Enables the whole module.
	│	:Disable() - Disables the whole module.
	│	:IsEnabled(): boolean - Returns ShiftLock's enabled state.
	└	:ToggleShiftLock(Enable: boolean?) - Toggles the ShiftLock, if Enable parameter is provided then ShiftLock will be toggled to it.
		
		
--]]