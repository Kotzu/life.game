-- Item registry. `weight` is in grams; `stack` controls whether the item
-- can stack in a single inventory slot; `usable` items can be consumed
-- via the framework's UseItem flow.
LifeItems = {
    water = {
        label = 'Water Bottle',
        weight = 500,
        stack = true,
        usable = true,
        description = 'Restores thirst.',
    },
    bread = {
        label = 'Bread',
        weight = 200,
        stack = true,
        usable = true,
        description = 'Restores hunger.',
    },
    burger = {
        label = 'Burger',
        weight = 300,
        stack = true,
        usable = true,
        description = 'Restores a lot of hunger.',
    },
    bandage = {
        label = 'Bandage',
        weight = 100,
        stack = true,
        usable = true,
        description = 'Stops light bleeding and restores some health.',
    },
    phone = {
        label = 'Phone',
        weight = 250,
        stack = false,
        usable = false,
        description = 'A smartphone.',
    },
    repairkit = {
        label = 'Repair Kit',
        weight = 2500,
        stack = true,
        usable = true,
        description = 'Repairs a vehicle engine.',
    },
    lockpick = {
        label = 'Lockpick',
        weight = 150,
        stack = true,
        usable = true,
        description = 'Might open a locked car door.',
    },
}
