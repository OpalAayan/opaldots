--//================================================================//
--//                       MONITORS                                 //
--//  Display routing and scaling.                                  //
--//================================================================//

-- Fallback: any unrecognized monitor gets preferred res, auto-placed
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = 1,
})
