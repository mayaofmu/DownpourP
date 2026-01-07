local Menu = {} 


function Menu:Initialize(FrameHolder)
      local Tabs = FrameHolder.Tabs
      local Loadout = FrameHolder.Loadout
      local Teams = FrameHolder.Teams 

      local tabs = {
         {Name = "Loadout", Frame = Loadout},
         {Name = "Teams", Frame = Teams},
      }

      function Tabs:OnTabSelected(TabName)
         print("Tab selected: " .. TabName)
      end


      

end


return Menu 