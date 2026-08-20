--//================================================================//
--//                       MONITORS                                 //
--//  Display routing and scaling.                                  //
--//================================================================//

-- Laptop Monitor (LVDS-1)
hl.monitor({
	output = "LVDS-1",
	mode = "1366x768@60.00",
	position = "0x0",
	scale = 1,
	transform = 0,
})

-- External Monitor (DP-3) forced to 1920x1080@60Hz
-- Positioned to the right of the laptop (1366 pixels over)
hl.monitor({
	output = "DP-3",
	mode = "1920x1080@75.00",
	position = "1366x0",
	scale = 1.2,
	transform = 0,
})
