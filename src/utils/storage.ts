// Local storage utilities for persisting app data

const STORAGE_KEYS = {
  TASKS: 'gamified-life-tasks',
  HABITS: 'gamified-life-habits',
  POINTS: 'gamified-life-points',
  LEVEL: 'gamified-life-level',
  ACHIEVEMENTS: 'gamified-life-achievements',
  REWARDS: 'gamified-life-rewards'
} as const

export const storage = {
  // Save data to localStorage
  set: <T>(key: string, value: T): void => {
    try {
      localStorage.setItem(key, JSON.stringify(value))
    } catch (error) {
      console.error(`Failed to save ${key} to localStorage:`, error)
    }
  },

  // Get data from localStorage
  get: <T>(key: string, defaultValue: T): T => {
    try {
      const item = localStorage.getItem(key)
      return item ? JSON.parse(item) : defaultValue
    } catch (error) {
      console.error(`Failed to get ${key} from localStorage:`, error)
      return defaultValue
    }
  },

  // Remove data from localStorage
  remove: (key: string): void => {
    try {
      localStorage.removeItem(key)
    } catch (error) {
      console.error(`Failed to remove ${key} from localStorage:`, error)
    }
  }
}

export const appStorage = {
  // Tasks
  saveTasks: (tasks: any[]) => storage.set(STORAGE_KEYS.TASKS, tasks),
  getTasks: () => storage.get(STORAGE_KEYS.TASKS, []),
  
  // Habits
  saveHabits: (habits: any[]) => storage.set(STORAGE_KEYS.HABITS, habits),
  getHabits: () => storage.get(STORAGE_KEYS.HABITS, []),
  
  // Points
  savePoints: (points: number) => storage.set(STORAGE_KEYS.POINTS, points),
  getPoints: () => storage.get(STORAGE_KEYS.POINTS, 0),
  
  // Level
  saveLevel: (level: number) => storage.set(STORAGE_KEYS.LEVEL, level),
  getLevel: () => storage.get(STORAGE_KEYS.LEVEL, 1),
  
  // Achievements
  saveAchievements: (achievements: any[]) => storage.set(STORAGE_KEYS.ACHIEVEMENTS, achievements),
  getAchievements: () => storage.get(STORAGE_KEYS.ACHIEVEMENTS, []),
  
  // Rewards
  saveRewards: (rewards: any[]) => storage.set(STORAGE_KEYS.REWARDS, rewards),
  getRewards: () => storage.get(STORAGE_KEYS.REWARDS, [])
}

export default storage
