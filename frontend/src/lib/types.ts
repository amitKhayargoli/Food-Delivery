export type AppRole = 'CUSTOMER' | 'DELIVERY_BOY' | 'RESTAURANT_OWNER' | 'ADMIN'
export type UserStatus = 'ACTIVE' | 'INACTIVE' | 'SUSPENDED' | 'PENDING' | 'REJECTED'

export interface UserRecord {
  id: string
  username: string
  email: string
  phone: string | null
  role: AppRole
  status: string
  created_at: string
  updated_at: string
}

export interface CreateUserPayload {
  username: string
  email: string
  phone?: string
  password: string
  role: AppRole
}

export interface StatusUpdatePayload {
  status: UserStatus
}

export interface UpdateUserPayload {
  username?: string
  email?: string
  phone?: string
  role?: AppRole
  status?: UserStatus
}
