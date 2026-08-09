-- Job definitions shared between client and server.
-- grades are 0-indexed; grade 0 is the entry rank.
LifeJobs = {
    unemployed = {
        label = 'Unemployed',
        grades = {
            [0] = { label = 'Unemployed', salary = 50 },
        },
    },
    police = {
        label = 'Los Santos Police',
        grades = {
            [0] = { label = 'Cadet',      salary = 150 },
            [1] = { label = 'Officer',    salary = 250 },
            [2] = { label = 'Sergeant',   salary = 350 },
            [3] = { label = 'Lieutenant', salary = 450 },
            [4] = { label = 'Chief',      salary = 600, isboss = true },
        },
    },
    ambulance = {
        label = 'Emergency Medical Services',
        grades = {
            [0] = { label = 'Trainee',   salary = 150 },
            [1] = { label = 'Paramedic', salary = 250 },
            [2] = { label = 'Doctor',    salary = 400 },
            [3] = { label = 'Chief',     salary = 550, isboss = true },
        },
    },
    mechanic = {
        label = 'Mechanic',
        grades = {
            [0] = { label = 'Apprentice', salary = 120 },
            [1] = { label = 'Mechanic',   salary = 200 },
            [2] = { label = 'Shop Owner', salary = 350, isboss = true },
        },
    },
    taxi = {
        label = 'Taxi Company',
        grades = {
            [0] = { label = 'Driver',  salary = 120 },
            [1] = { label = 'Manager', salary = 250, isboss = true },
        },
    },
}
