PropertiesTable = {}
ApartmentsTable = {}

exports('GetProperties', function() return PropertiesTable end)
exports('GetApartments', function() return ApartmentsTable end)

Config = {}
Config.VersionCheck = true

-- Provedor usado quando o grupo está em "target".
Config.Target = "pr" -- "pr" (PR Bridge nativo) ou "qb" para portas e móveis legados

-- Escolha "target" ou "interact" em cada grupo. Vale para todos os imóveis.
Config.Interactions = {
    general = "interact",     -- Entradas, saídas, campainhas, recepções e segurança
    furniture = "interact",   -- Armários, guarda-roupas, baús e cofres
    hygiene = "interact",   -- Chuveiros, pias, sanitários e pontos cadastrados
}
Config.Notify = "pr" -- "pr" or "qb"
Config.Radial = "pr" -- "pr" or "qb"
Config.Inventory = "ox" -- "ox" or "qb"
Config.Logs = "pr" -- "pr" or "qb"

-- Anyone provided with keys to a property has the ability to modify its furnishings.
Config.AccessCanEditFurniture = true

-- Senha inicial aplicada automaticamente a todo cofre comprado.
-- Pode ser alterada pelo dono ou administrador na interação do cofre.
Config.FurnitureSafeDefaultPassword = '0000'

-- Gestao da propriedade
-- Percentuais de repasse: cada tabela precisa somar exatamente 100.
-- Use os identificadores reais das contas cadastradas no banco.
Config.impostos = { ['realestate'] = 70, ['government'] = 30 }
Config.security = { ['police'] = 100 --[[, ['leo'] = 30]] }
Config.MinimumResalePercent = 50 -- % do valor pago pelo proprietário atual
Config.TransferTaxPercent = 10 -- padrão; o boss pode alterar no tablet
Config.adminPrice = 500
Config.keyPrice = 500 -- valor cobrado do dono/administrador ao emitir uma chave
Config.keyPaymentAccount = 'bank' -- bank, cash (ou money)
Config.keyGrantDistance = 5.0 -- distancia maxima entre quem gerencia e quem recebe acesso
Config.PropertyTaxes = {
    paymentAccount = 'bank',
    checkIntervalMinutes = 1,
    cutServicesOnDebt = true, -- corta luz/agua enquanto o respectivo saldo estiver pendente
    luz = { label = HousingT('Luz'), defaultAmount = 100, defaultIntervalDays = 1 },
    agua = { label = HousingT('Agua'), defaultAmount = 100, defaultIntervalDays = 1 },
    security = { label = HousingT('Segurança'), defaultAmount = 100, defaultIntervalDays = 1 },
    iptu = { label = HousingT('IPTU'), defaultAmount = 100, defaultIntervalDays = 1 },
}

-- Draw the poly for the property
Config.DebugMode = false

function Debug(...)
    if Config.DebugMode then
        print(...)
    end
end

-- Log System
Config.EnableLogs = true

-- Enables Dynamic Doors
Config.DynamicDoors = false

Config.PoliceJobNames = {  -- add multiple police jobs that are allowed to raid properties!
    "police",
    -- "police2",
    -- "police3",
}

Config.MinGradeToRaid = 3  -- Minimum grade to raid a property

Config.RaidTimer = 5  -- 5 minutes

Config.RaidItem = "police_stormram"  -- The item required to raid a property

-- If you are using ox_inventory, it is encouraged to use the consume property within data/items.lua and keeping this config option false
Config.ConsumeRaidItem = false          -- Whether or not to consume the raid item upon successful entry.

-- Set your Real Estate jobs here
Config.RealtorJobNames = { -- add multiple realestate jobs that are allowed to sell properties!
    "realestate",
    -- "realestate2",
    -- "realestate3",
}

-- If you are utilizing qb-banking and wish for the funds to be deposited directly into the Realestate bank account, set this value to true. 
-- In case you are using an alternative Boss Menu, replace the qb-banking export with the appropriate script export or event.
Config.QBManagement = false

-- Comissão do corretor por cargo; o restante da venda vai para Config.impostos.
Config.Commissions = {
    [0] = 0.05, -- 5% commision for each sale
    [1] = 0.10,
    [2] = 0.15,
    [3] = 0.20,
    [4] = 0.25,
}

-- Set this value to false if you don't want to assign a starting apartment.
Config.StartingApartment = true

--- With this enabled, the customizer will open when starting apartment is false.
Config.ShowCustomizerWhenNoStartingApartment = true

Config.Apartments = {
    ["Integrity Way"] = {
        label = "Integrity Way",
        door = { x = 269.73, y = -640.75, z = 42.02, h = 249.07, length = 1, width = 2 },
        imgs = {
            {
                url = "https://files.fivemerr.com/images/e5a352a3-afb1-4452-ab52-e239e53d901a.png",
                label = HousingT("Outside"),
            },
        },
        shell = HousingT("Apartment Furnished"),
    },

    ["South Rockford Drive"] = {
        label = "South Rockford Drive",
        door = { x = -667.02, y = -1105.24, z = 14.63, h = 242.32, length = 1, width = 2 },
        imgs = {
            {
                url = "https://files.fivemerr.com/images/aa88b5df-c4c8-4706-beb0-8d8197e0ccff.png",
                label = HousingT("Outside"),
            },
        },
        shell = HousingT("Apartment Furnished"),
    },

    ['Morningwood Blvd'] = {
        label = 'Morningwood Blvd',
        door = { x = -1288.52, y = -430.51, z = 35.15, h = 124.81, length = 1, width = 2 },
        imgs = {
            {
                url = "https://files.fivemerr.com/images/c53dbc10-d161-4b34-a095-316949588f33.png",
                label = HousingT("Outside"),
            },
        },
        shell = HousingT("Apartment Furnished"),
    },

    ['Tinsel Towers'] = {
        label = 'Tinsel Towers',
        door = { x = -619.29, y = 37.69, z = 43.59, h = 181.03, length = 1, width = 2 },
        imgs = {
            {
                url = "https://files.fivemerr.com/images/0663c90e-2e90-426d-80ea-a780727b4a76.png",
                label = HousingT("Outside"),
            },
        },
        shell = HousingT("Apartment Furnished"),
    },

    ['Fantastic Plaza'] = {
        label = 'Fantastic Plaza',
        door = { x = 291.517, y = -1078.674, z = 29.405, h = 270.75, length = 1, width = 2 },
        imgs = {
            {
                url = "https://files.fivemerr.com/images/d618a25e-2f88-47c5-b065-515cbd34cb3f.png",
                label = HousingT("Outside"),
            },
        },
        shell = HousingT("Apartment Furnished"),
    },

    ---ipl
    ['Modern 1 Apartment'] = {
        label = HousingT('Modern 1 Apartment'),
        door = { x = -771.18, y = 319.64, z = 85.66, h = 351.95, length = 1, width = 2 },
        imgs = {
            {
                url = "https://files.fivemerr.com/images/d618a25e-2f88-47c5-b065-515cbd34cb3f.png",
                label = HousingT("Outside"),
            },
        },
        interior = vector3(-786.8663, 315.7642, 217.6385),
        thickness = 7.5,
        zone = {
            vector3(-787.3, 317.37, 219.5),
            vector3(-787.29, 314.34, 219.5),
            vector3(-780.56, 314.15, 219.5),
            vector3(-780.54, 343.62, 219.5),
            vector3(-793.98, 343.54, 219.5),
            vector3(-793.33, 333.82, 219.5),
            vector3(-794.68, 339.83, 219.5),
            vector3(-800.69, 339.94, 219.5),
            vector3(-807.54, 334.88, 219.5),
            vector3(-807.29, 331.75, 219.5),
            vector3(-799.8, 321.23, 219.5)
        },
        shell = "mlo",
    },
}

-- Shells provided by K4MB1 https://www.k4mb1maps.com/
Config.Shells = {
    ["mlo"] = {
        label = "Mlo",
        doorOffset = { x = -0.5, y = -2.3, z = 0.0, h = 90.0, width = 1.5 },
        stash = {
            maxweight = 100000,
            slots = 12,
        },
        imgs = {
            {
                url = "https://files.fivemerr.com/images/e39bd4a6-bc3f-41e7-876e-cc03d77f953b.jpg",
                label = HousingT("Motel"),
            },
        }
    },

    ["Standard Motel"] = {
        label = HousingT("Standard Motel"),
        hash = `standardmotel_shell`,
        doorOffset = { x = -0.5, y = -2.3, z = 0.0, h = 90.0, width = 1.5 },
        stash = {
            maxweight = 100000,
            slots = 12,
        },
        imgs = {
            {
                url = "https://files.fivemerr.com/images/fb1f1038-2b38-4cee-b031-e0bca4c108ed.webp",
                label = HousingT("Motel"),
            },
        }
    },

    ["Modern Hotel"] = {
        label = HousingT("Modern Hotel"),
        hash = `modernhotel_shell`,
        doorOffset = { x = 4.98, y = 4.35, z = 0.0, h = 179.79, width = 2.0  },
        stash = {
            maxweight = 150000,
            slots = 20,
        },
        imgs = {
            {
                url = "https://files.fivemerr.com/images/33d4b3e2-9c5a-43d8-a43e-f111f25a62df.webp",
                label = HousingT("Angle 1"),
            },
            {
                url = "https://files.fivemerr.com/images/7dc8efd9-d2c7-4878-a7d7-74d69e47cc96.webp",
                label = HousingT("Angle 2"),
            },
        }
    },

    ["Apartment Furnished"] = {
        label = HousingT("Apartment Furnished"),
        hash = `furnitured_midapart`,
        doorOffset = { x = 1.44, y = -10.25, z = 0.0, h = 0.0, width = 1.5  },
        stash = {
            maxweight = 200000,
            slots = 25,
        },
        imgs = {
            {
                url = "https://files.fivemerr.com/images/884a835f-9d5d-4121-8576-b23c51f48a00.webp",
                label = HousingT("Bathroom"),
            },
            {
                url = "https://files.fivemerr.com/images/3381c0b8-1e57-4aa7-bb61-5b1202523db9.webp",
                label = HousingT("Bedroom"),
            },
            {
                url = "https://files.fivemerr.com/images/5b5b66a5-50f5-437c-9fb8-ebb5a7ecec11.webp",
                label = HousingT("Entrance"),
            },
            {
                url = "https://files.fivemerr.com/images/5e07d5e9-c069-4db1-a677-d2d0a02def70.webp",
                label = HousingT("Kitchen and Dining"),
            },
            {
                url = "https://files.fivemerr.com/images/41998ae1-e2f0-4e8a-b9e3-4613e46b3356.webp",
                label = HousingT("Living Room Angle 1"),
            },
            {
                url = "https://files.fivemerr.com/images/b60325be-e75c-4985-89f2-6e2dfe65951c.webp",
                label = HousingT("Living Room Angle 2"),
            },
        },
    },

    ["Apartment Unfurnished"] = {
        label = HousingT("Apartment Unfurnished"),
        hash = `shell_v16mid`,
        doorOffset = { x = 1.34, y = -14.36, z = -0.5, h = 354.08, width = 1.5  },
        stash = {
            maxweight = 200000,
            slots = 25,
        },
        imgs = {
            {
                url = "https://files.fivemerr.com/images/90238f10-e65e-4c89-a879-6be664194258.webp",
                label = HousingT("Bathroom"),
            },
            {
                url = "https://files.fivemerr.com/images/edfcda70-bca6-419c-84b5-11e173e9edc3.webp",
                label = HousingT("Bedroom"),
            },
            {
                url = "https://files.fivemerr.com/images/aed9c846-7314-4869-948f-3262e1d141ee.webp",
                label = HousingT("Entrance"),
            },
            {
                url = "https://files.fivemerr.com/images/a51a4844-2141-472f-bde2-0c07a940ddd0.webp",
                label = HousingT("Kitchen"),
            },
            {
                url = "https://files.fivemerr.com/images/bcbc0b02-5648-4eb2-bd16-5585a2f14e12.webp",
                label = HousingT("Living Room"),
            },
        },
    },

    ["Apartment 2 Unfurnished"] = {
        label = HousingT("Apartment 2 Unfurnished"),
        hash = `shell_v16low`,
        doorOffset = { x = 4.69, y = -6.5, z = -1.0, h = 358.50, width = 1.5  },
        stash = {
            maxweight = 200000,
            slots = 25,
        },
        imgs = {
            {
                url = "https://files.fivemerr.com/images/6e111f0d-a663-4baf-9f64-e38e8c2c6cf8.webp",
                label = HousingT("Entrance"),
            },
            {
                url = "https://files.fivemerr.com/images/5202fb7b-c178-4a30-8113-2b5d7bd45ea8.webp",
                label = HousingT("Kitchen"),
            },
            {
                url = "https://files.fivemerr.com/images/f3676be4-49c5-4b4a-9c56-e5ceb228329c.webp",
                label = HousingT("Living Room"),
            },
        },
    },

    ["Garage"] = {
        label = HousingT("Garage"),
        hash = `shell_garagem`,
        doorOffset = { x = 14.0, y = 1.7, z = -0.76, h = 88.49, width = 2.0  },
        stash = {
            maxweight = 500000,
            slots = 50,
        },
        imgs = {
            {
                url = "https://files.fivemerr.com/images/dad29136-63f4-486a-8b0c-73bf6717ac10.webp",
                label = HousingT("Entrance"),
            },
            {
                url = "https://files.fivemerr.com/images/b94621eb-1c3d-4cd6-b849-bd74fe94b601.webp",
                label = HousingT("Garage"),
            },
        },
    },

    ["Office"] = {
        label = HousingT("Office"),
        hash = `shell_office1`,
        doorOffset = { x = 1.2, y = 4.90, z = -0.73, h = 180.0, width = 2.0  },
        stash = {
            maxweight = 250000,
            slots = 30,
        },
        imgs = {
            {
                url = "https://files.fivemerr.com/images/b6894303-56a5-4ed6-9c3c-3108563b32b5.webp",
                label = HousingT("Entance"),
            },
            {
                url = "https://files.fivemerr.com/images/938945b9-fa86-4b88-8264-870c8d25b780.webp",
                label = HousingT("Office"),
            },
        },
    },

    ["Store"] = {
        label = HousingT("Store"),
        hash = `shell_store1`,
        doorOffset = { x = -2.69, y = -4.56, z = -0.62, h = 1.91, width = 2.0  },
        stash = {
            maxweight = 500000,
            slots = 50,
        },
        imgs = {
            {
                url = "https://files.fivemerr.com/images/4b071bca-fd50-4d41-ba83-f9080c2da0be.webp",
                label = HousingT("Room 1"),
            },
            {
                url = "https://files.fivemerr.com/images/ef1ccd1f-85b8-4681-abdd-c798b73eb1e2.webp",
                label = HousingT("Room 2"),
            },
        },
    },

    ["Warehouse"] = {
        label = HousingT("Warehouse"),
        hash = `shell_warehouse1`,
        doorOffset = { x = -8.96, y = 0.11, z = -0.95, h = 270.64, width = 2.0  },
        stash = {
            maxweight = 1000000,
            slots = 100,
        },
        imgs = {
            {
                url = "https://files.fivemerr.com/images/35d75b18-aa4f-4226-9b42-8e8ceb723946.webp",
                label = HousingT("Angle 1"),
            },
            {
                url = "https://files.fivemerr.com/images/b25f0c5d-9c6a-43e4-b082-eac8d1730f98.webp",
                label = HousingT("Angle 2"),
            },
        },
    },

    ["Container"] = {
        label = HousingT("Container"),
        hash = `container_shell`,
        doorOffset = { x = 0.05, y = -5.7, z = -0.22, h = 1.7, width = 2.2  },
        stash = {
            maxweight = 500000,
            slots = 100,
        },
        imgs = {
            {
                url = "https://files.fivemerr.com/images/29930411-18a3-4e39-bb4b-80bb5ca9c233.webp",
                label = HousingT("Container"),
            },
        },
    },

    ["2 Floor House"] = {
        label = HousingT("2 Floor House"),
        hash = `shell_michael`,
        doorOffset = { x = -9.6, y = 5.63, z = -4.07, h = 268.55, width = 2.0  },
        stash = {
            maxweight = 300000,
            slots = 50,
        },
        imgs = {
            {
                url = "https://files.fivemerr.com/images/5b3fc4b4-fbc7-4020-bb63-50d5bd5ae1ca.webp",
                label = HousingT("Bathroom"),
            },
            {
                url = "https://files.fivemerr.com/images/a7537dd9-94d7-47ad-bd74-ae3c7fc728d3.webp",
                label = HousingT("Entrance"),
            },
            {
                url = "https://files.fivemerr.com/images/75f3cc72-ace3-40af-836f-40112fde2ba8.webp",
                label = HousingT("Floor 2"),
            },
            {
                url = "https://files.fivemerr.com/images/348e6af7-f247-49a0-a4d4-e99995f20d7f.webp",
                label = HousingT("Kitchen"),
            },
            {
                url = "https://files.fivemerr.com/images/9e8689a9-5860-41b5-b5f1-df9f68cfaea2.webp",
                label = HousingT("Living Room"),
            },
            {
                url = "https://files.fivemerr.com/images/e4cb286e-acb2-42a4-b41a-e31b0482d7a7.webp",
                label = HousingT("Room 1"),
            },
            {
                url = "https://files.fivemerr.com/images/b3c0eeec-b5e7-4f41-a82b-f4bdf954c1a7.webp",
                label = HousingT("Room 2"),
            },
            {
                url = "https://files.fivemerr.com/images/0f327cda-e432-4fd3-9002-973544f3b46a.webp",
                label = HousingT("Room 3"),
            },
            {
                url = "https://files.fivemerr.com/images/5e2e0778-2709-4bb0-a17d-ac6154fdbd77.webp",
                label = HousingT("Room 3 Dresser"),
            },
        },
    },

    ["House 1"] = {
        label = HousingT("House 1"),
        hash = `shell_frankaunt`,
        doorOffset = { x = -0.34, y = -5.97, z = -0.57, h = 357.23, width = 2.0  },
        stash = {
            maxweight = 200000,
            slots = 50,
        },
        imgs = {
            {
                url = "https://files.fivemerr.com/images/5b3fc4b4-fbc7-4020-bb63-50d5bd5ae1ca.webp",
                label = HousingT("Bathroom"),
            },
            {
                url = "https://files.fivemerr.com/images/71df6160-68b0-4233-a8df-abc0b76401a0.webp",
                label = HousingT("Dining Room"),
            },
            {
                url = "https://files.fivemerr.com/images/5830cc1b-fd3b-4ff5-8e7b-4a9c81725daf.webp",
                label = HousingT("Entrance"),
            },
            {
                url = "https://files.fivemerr.com/images/7be14444-b37c-4ad1-b215-e126525f23b0.webp",
                label = HousingT("Kitchen"),
            },
            {
                url = "https://files.fivemerr.com/images/f7e3d82b-26d3-4550-acdb-a5d6f2aacdce.webp",
                label = HousingT("Living Room"),
            },
            {
                url = "https://files.fivemerr.com/images/b0d64302-f411-40fd-9d08-b2c19473960b.webp",
                label = HousingT("Room 1"),
            },
            {
                url = "https://files.fivemerr.com/images/5b3fc4b4-fbc7-4020-bb63-50d5bd5ae1ca.webp",
                label = HousingT("Room 2"),
            },
        },
    },

    ["House 2"] = {
        label = HousingT("House 2"),
        hash = `shell_ranch`,
        doorOffset = { x = -1.23, y = -5.54, z = -1.1, h = 272.21, width = 2.0  },
        stash = {
            maxweight = 500000,
            slots = 50,
        },
        imgs = {
            {
                url = "https://files.fivemerr.com/images/5f9b5a4a-d607-4fef-954e-aab0c25457d6.webp",
                label = HousingT("Entrance"),
            },
            {
                url = "https://files.fivemerr.com/images/31be06b1-d092-41e4-bd90-b23ca06fdf51.webp",
                label = HousingT("Hallway"),
            },
            {
                url = "https://files.fivemerr.com/images/a498685d-31bc-487c-83be-d479529dc36e.webp",
                label = HousingT("Kitchen"),
            },
            {
                url = "https://files.fivemerr.com/images/87cbc4d9-e3aa-4709-9504-26a56816b3d9.webp",
                label = HousingT("Main Area"),
            },
            {
                url = "https://files.fivemerr.com/images/2bc3d6b6-3d22-4865-82dd-594c2d48fad9.webp",
                label = HousingT("Room"),
            },
        },
    },

    ["House 3"] = {
        label = HousingT("House 3"),
        hash = `shell_lester`,
        doorOffset = { x = -1.61, y = -6.02, z = -0.37, h = 357.7, width = 2.0  },
        stash = {
            maxweight = 15000,
            slots = 20,
        },
        imgs = {
            {
                url = "https://files.fivemerr.com/images/c43c554f-8bc4-4028-9d6e-599aff60c4e8.jpeg",
                label = HousingT("Angle 1"),
            },
            {
                url = "https://files.fivemerr.com/images/a2cf4128-2d3a-4aa4-a19b-186edc7813c5.jpeg",
                label = HousingT("Angle 2"),
            },
            {
                url = "https://files.fivemerr.com/images/5a669e54-2080-45fd-bf8c-0dd9075e3258.jpeg",
                label = HousingT("Entrance"),
            },
        },
    },

    ["House 4"] = {
        label = HousingT("House 4"),
        hash = `shell_trevor`,
        doorOffset = { x = 0.2, y = -3.82, z = -0.41, h = 358.4, width = 2.0  },
        stash = {
            maxweight = 10000,
            slots = 12,
        },
        imgs = {
            {
                url = "https://files.fivemerr.com/images/cfc6d14e-d198-427a-a45c-fa1e0b1a8121.webp",
                label = HousingT("Bathroom"),
            },
            {
                url = "https://files.fivemerr.com/images/30f5c5b2-8591-4fef-9ebf-2095c508605b.webp",
                label = HousingT("Entrance"),
            },
            {
                url = "https://files.fivemerr.com/images/9babd5ff-7421-4a38-9b86-4900b3c0901f.webp",
                label = HousingT("Kitchen"),
            },
            {
                url = "https://files.fivemerr.com/images/d2dda0ca-aa9d-4826-9cd0-be6e1ee37f6b.webp",
                label = HousingT("Living Room"),
            },
            {
                url = "https://files.fivemerr.com/images/9309b115-3266-48af-952d-cdcb39573b3e.webp",
                label = HousingT("Room 1"),
            },
            {
                url = "https://files.fivemerr.com/images/2c5625ed-af05-49f3-a7ca-256fef131988.webp",
                label = HousingT("Room 2"),
            },
        },
    },

    ["Trailer"] = {
        label = HousingT("Trailer"),
        hash = `shell_trailer`,
        doorOffset = { x = -1.27, y = -2.08, z = -0.48, h = 358.84, width = 2.0  },
        stash = {
            maxweight = 10000,
            slots = 12,
        },
        imgs = {
            {
                url = "https://files.fivemerr.com/images/a52b4053-ffb5-430c-a578-1aa09ebea723.webp",
                label = HousingT("Entrance and Kitchen"),
            },
            {
                url = "https://files.fivemerr.com/images/603bc770-1a8f-43a1-b8d2-d15f9af87f59.webp",
                label = HousingT("Main"),
            },
            {
                url = "https://files.fivemerr.com/images/222716c0-9a27-4269-8c5b-698c218ec2d9.webp",
                label = HousingT("Room"),
            },
        },
    },
}

-- Interiores adicionais.
-- Formato simples: ['Nome exibido'] = 'nome_do_modelo'
-- O interior passa a aparecer automaticamente no criador do forge-realtor.
Config.CustomShells = {
    ['Apartamento Luxo Jordqn'] = 'apart_luxe_1',
    ['Motel Simples Jordqn'] = 'motel_low',
    ['Galpao Pequeno Jordqn'] = 'warehouse_small',
    ['Laboratorio Vazio Jordqn'] = 'coke_business_empty',

    -- Formato avancado para ajustar uma entrada fora da origem:
    -- ['Minha Shell'] = {
    --     model = 'minha_shell',
    --     doorOffset = { x = 0.0, y = 0.0, z = 0.0, h = 0.0, width = 1.5 },
    --     stash = { maxweight = 100000, slots = 20 },
    --     imgs = { { url = 'https://exemplo.com/interior.webp', label = 'Interior' } },
    -- },
}

Config.CustomShellDefaults = {
    doorOffset = { x = 0.0, y = 0.0, z = 0.0, h = 0.0, width = 1.5 },
    stash = { maxweight = 100000, slots = 20 },
    imgs = {},
}

local function copyShellTable(value)
    local result = {}
    for key, item in pairs(value or {}) do
        result[key] = type(item) == 'table' and copyShellTable(item) or item
    end
    return result
end

for label, definition in pairs(Config.CustomShells or {}) do
    local details = type(definition) == 'table' and definition or {}
    local model = type(definition) == 'string' and definition or details.model or details.shell

    if model and model ~= '' then
        Config.Shells[label] = {
            label = details.label or label,
            hash = type(model) == 'number' and model or joaat(model),
            doorOffset = copyShellTable(details.doorOffset or Config.CustomShellDefaults.doorOffset),
            stash = copyShellTable(details.stash or Config.CustomShellDefaults.stash),
            imgs = copyShellTable(details.imgs or Config.CustomShellDefaults.imgs),
        }
    else
        print((HousingT('[forge-housing] CustomShell invalida: %s')):format(tostring(label)))
    end
end
Config.FurnitureTypes = {
    ["storage"] = function(entity, property_id, shell)
        HousingInteractions.addFurniture(entity, {{
            label = HousingT("Storage"), icon = "fas fa-box-open",
            onSelect = function()
                local stashConfig = Config.Shells[shell].stash
                Framework[Config.Inventory].OpenInventory("property_" .. property_id, stashConfig, property_id)
            end,
        }})
    end,

    ["clothing"] = function(entity)
        HousingInteractions.addFurniture(entity, {{
            label = HousingT("Clothing"), icon = "fas fa-shirt",
            onSelect = function()
                local heading = GetEntityHeading(pr_lib.cache.ped)
                SetEntityHeading(pr_lib.cache.ped, heading - 180.0)
                TriggerEvent("forge-appearance:client:openOutfitMenu")
            end,
        }})
    end,
}

-- O catalogo autoritativo esta em data/furniture_catalog.json.
-- Mantido apenas para compatibilidade com scripts externos antigos.
Config.Furnitures = {}

Config.DoorGroup = 'forge-housing'

HousingCategories={house=true,apartment=true,hotel=true,chalet=true,trailer=true}
function NormalizeHousingCategory(category,apartment)
    if HousingCategories[category] then return category end
    return type(apartment)=='string' and apartment~='' and 'apartment' or 'house'
end

-- Fallback until the realtor boss defines a specific price in the IPL catalogue.
Config.IPLDecor = Config.IPLDecor or { defaultPrice = 1000 }
Config.IPLDecor.cashItem = Config.IPLDecor.cashItem or 'money'

-- Extra placement margin at shell/IPL walls and ceilings, in meters.
Config.FurniturePlacementTolerance = 0.5
