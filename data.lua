-- Define the custom hotkey that the player can press to call their car.
data:extend({
  {
    type = "custom-input",
    name = "vehicle-valet-return",
    key_sequence = "SHIFT + RETURN",  -- Change this to whatever you prefer
    consuming = "none"
  },
  {
    type = "custom-input",
    name = "vehicle-valet-numpad-enter",
    key_sequence = "SHIFT + KP_ENTER",
    consuming = "none"
  }
})
