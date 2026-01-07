local MarketplaceService = game:GetService("MarketplaceService")

for _, animation in workspace.Rigc:GetChildren() do
	if not animation:IsA("Animation") then
		continue
	end

	local assetId = tonumber(animation.AnimationId:match("%d+"))
	if not assetId then
		continue
	end

	local success, result = pcall(MarketplaceService.GetProductInfo, MarketplaceService, assetId, Enum.InfoType.Asset)
	if success and result then
		animation.Name = result.Name
	end
end