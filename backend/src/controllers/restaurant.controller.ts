import { Request, Response } from 'express';
import jwt from 'jsonwebtoken';
import { supabase } from '../db/supabase';
import { notifyUser } from '../services/fcm.service';

const JWT_SECRET = process.env.JWT_SECRET || 'supersecretkey';

interface JwtPayload {
  id: string;
  role: string;
}

function getUserId(req: Request): string | null {
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) return null;

  try {
    const payload = jwt.verify(authHeader.slice(7), JWT_SECRET) as JwtPayload;
    return payload.id;
  } catch {
    return null;
  }
}

// ──────────────────────────────────────────────
// POST /api/restaurant-applications
// Submit a new restaurant owner application
// ──────────────────────────────────────────────
export const applyForRestaurant = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const {
      restaurant_name,
      owner_name,
      phone,
      email,
      address,
      pan_number,
      pan_certificate_url,
      description,
      logo_url,
      cover_image_url,
      open_time,
      close_time,
      cuisine_type,
    } = req.body;

    // Validate required fields
    const required = ['restaurant_name', 'owner_name', 'phone', 'email', 'address', 'pan_number', 'pan_certificate_url'];
    const missing = required.filter((f) => !req.body[f]);
    if (missing.length > 0) {
      res.status(400).json({ error: `Missing required fields: ${missing.join(', ')}` });
      return;
    }

    // Check if user already has a pending/approved application
    const { data: existing } = await supabase.admin
      .from('restaurant_applications')
      .select('id, status')
      .eq('user_id', userId)
      .in('status', ['PENDING', 'APPROVED'])
      .limit(1)
      .maybeSingle();

    if (existing) {
      res.status(409).json({
        error: `You already have an ${existing.status.toLowerCase()} application.`,
        status: existing.status,
      });
      return;
    }

    // Check if restaurant name is taken
    const { data: nameConflict } = await supabase.admin
      .from('restaurant_applications')
      .select('id')
      .eq('restaurant_name', restaurant_name)
      .in('status', ['PENDING', 'APPROVED'])
      .limit(1)
      .maybeSingle();

    if (nameConflict) {
      res.status(409).json({ error: 'This restaurant name is already registered.' });
      return;
    }

    const { data: application, error } = await supabase.admin
      .from('restaurant_applications')
      .insert({
        user_id: userId,
        restaurant_name,
        owner_name,
        phone,
        email,
        address,
        pan_number,
        pan_certificate_url,
        description: description || null,
        logo_url: logo_url || null,
        cover_image_url: cover_image_url || null,
        open_time: open_time || null,
        close_time: close_time || null,
        cuisine_type: cuisine_type || null,
        status: 'PENDING',
      })
      .select('id, restaurant_name, status, created_at')
      .single();

    if (error) {
      console.error('Application insert error:', error);
      res.status(500).json({ error: 'Failed to submit application.' });
      return;
    }

    res.status(201).json({
      message: 'Application submitted successfully. Awaiting admin review.',
      application,
    });
  } catch (error) {
    console.error('Apply for restaurant error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// GET /api/restaurant-applications/my
// Get the current user's application
// ──────────────────────────────────────────────
export const getMyApplication = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const { data: application, error } = await supabase.admin
      .from('restaurant_applications')
      .select('*')
      .eq('user_id', userId)
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle();

    if (error) {
      console.error('Fetch application error:', error);
      res.status(500).json({ error: 'Failed to fetch application.' });
      return;
    }

    res.status(200).json({ application });
  } catch (error) {
    console.error('Get my application error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// GET /api/restaurant-applications
// Get all applications (admin only)
// ──────────────────────────────────────────────
export const getAllApplications = async (_req: Request, res: Response): Promise<void> => {
  try {
    const { data: applications, error } = await supabase.admin
      .from('restaurant_applications')
      .select('*, users(username, email, phone)')
      .eq('status', 'PENDING')
      .order('created_at', { ascending: false });

    if (error) {
      console.error('Fetch all applications error:', error);
      res.status(500).json({ error: 'Failed to fetch applications.' });
      return;
    }

    res.status(200).json(applications);
  } catch (error) {
    console.error('Get all applications error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// PATCH /api/restaurant-applications/:id/status
// Approve or reject an application (admin only)
// ──────────────────────────────────────────────
export const updateApplicationStatus = async (req: Request, res: Response): Promise<void> => {
  try {
    const { id } = req.params;
    const { status } = req.body;

    const validStatuses = ['APPROVED', 'REJECTED'];
    if (!validStatuses.includes(status)) {
      res.status(400).json({ error: `Status must be one of: ${validStatuses.join(', ')}` });
      return;
    }

    // Fetch the application
    const { data: application, error: fetchError } = await supabase.admin
      .from('restaurant_applications')
      .select('*')
      .eq('id', id)
      .maybeSingle();

    if (fetchError || !application) {
      res.status(404).json({ error: 'Application not found.' });
      return;
    }

    if (application.status !== 'PENDING') {
      res.status(409).json({ error: `Application has already been ${application.status.toLowerCase()}.` });
      return;
    }

    // Update the application status
    const { data: updated, error: updateError } = await supabase.admin
      .from('restaurant_applications')
      .update({ status })
      .eq('id', id)
      .select('id, restaurant_name, status')
      .single();

    if (updateError) {
      console.error('Status update error:', updateError);
      res.status(500).json({ error: 'Failed to update application status.' });
      return;
    }

    // If approved, update the user's role to RESTAURANT_OWNER
    if (status === 'APPROVED' && application.user_id) {
      console.log(`[RT-BACKEND] 🎉 Approving application "${application.restaurant_name}" for user ${application.user_id}`);
      console.log(`[RT-BACKEND]   └─ Updating user role: → RESTAURANT_OWNER`);

      const { error: roleError } = await supabase.admin
        .from('users')
        .update({ role: 'RESTAURANT_OWNER', status: 'ACTIVE' })
        .eq('id', application.user_id);

      if (roleError) {
        console.error('[RT-BACKEND] ❌ User role update error:', roleError);
        // Non-fatal — application is still approved
      } else {
        console.log(`[RT-BACKEND] ✅ User ${application.user_id} role updated to RESTAURANT_OWNER`);
        console.log(`[RT-BACKEND]   └─ Supabase Realtime should now broadcast this change`);

        // Send push notification to the user about their new role
        notifyUser(application.user_id, supabase.admin, {
          title: 'Application Approved 🎉',
          body: `Your restaurant "${application.restaurant_name}" has been approved! You now have owner access.`,
          data: {
            type: 'role_change',
            role: 'RESTAURANT_OWNER',
          },
        });
      }
    }

    // Send rejection notification
    if (status === 'REJECTED' && application.user_id) {
      console.log(`[RT-BACKEND] ❌ Rejected application "${application.restaurant_name}" for user ${application.user_id}`);
      notifyUser(application.user_id, supabase.admin, {
        title: 'Application Update',
        body: `Your restaurant "${application.restaurant_name}" application could not be approved at this time.`,
        data: {
          type: 'role_change',
          role: 'CUSTOMER',
        },
      });
    }

    res.status(200).json({
      message: `Application ${status.toLowerCase()} successfully.`,
      application: updated,
    });
  } catch (error) {
    console.error('Update application status error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// PUT /api/restaurant-applications/my
// Update the authenticated owner's restaurant profile
// ──────────────────────────────────────────────
export const updateRestaurant = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    // Find approved application for this user
    const { data: application, error: fetchError } = await supabase.admin
      .from('restaurant_applications')
      .select('id, restaurant_name, status')
      .eq('user_id', userId)
      .eq('status', 'APPROVED')
      .maybeSingle();

    if (fetchError || !application) {
      res.status(404).json({ error: 'No approved restaurant application found.' });
      return;
    }

    const {
      restaurant_name,
      owner_name,
      phone,
      email,
      address,
      description,
      logo_url,
      cover_image_url,
      open_time,
      close_time,
      cuisine_type,
    } = req.body;

    // Validate required fields
    if (restaurant_name !== undefined && restaurant_name.toString().trim().length === 0) {
      res.status(400).json({ error: 'Restaurant name cannot be empty.' });
      return;
    }

    // If changing restaurant name, check it's not taken by another approved application
    if (restaurant_name !== undefined && restaurant_name !== application.restaurant_name) {
      const { data: nameConflict } = await supabase.admin
        .from('restaurant_applications')
        .select('id')
        .eq('restaurant_name', restaurant_name)
        .eq('status', 'APPROVED')
        .neq('id', application.id)
        .limit(1)
        .maybeSingle();

      if (nameConflict) {
        res.status(409).json({ error: 'This restaurant name is already registered by another restaurant.' });
        return;
      }
    }

    // Build update object — only include fields that were sent
    const updates: Record<string, unknown> = {};
    if (restaurant_name !== undefined) updates.restaurant_name = restaurant_name;
    if (owner_name !== undefined) updates.owner_name = owner_name;
    if (phone !== undefined) updates.phone = phone;
    if (email !== undefined) updates.email = email;
    if (address !== undefined) updates.address = address;
    if (description !== undefined) updates.description = description;
    if (logo_url !== undefined) updates.logo_url = logo_url;
    if (cover_image_url !== undefined) updates.cover_image_url = cover_image_url;
    if (open_time !== undefined) updates.open_time = open_time;
    if (close_time !== undefined) updates.close_time = close_time;
    if (cuisine_type !== undefined) updates.cuisine_type = cuisine_type;
    updates.updated_at = new Date().toISOString();

    const { data: updated, error: updateError } = await supabase.admin
      .from('restaurant_applications')
      .update(updates)
      .eq('id', application.id)
      .select('*')
      .single();

    if (updateError) {
      console.error('Restaurant update error:', updateError);
      res.status(500).json({ error: 'Failed to update restaurant profile.' });
      return;
    }

    res.status(200).json({
      message: 'Restaurant profile updated successfully.',
      application: updated,
    });
  } catch (error) {
    console.error('Update restaurant error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// PATCH /api/restaurant-applications/my/accepting-orders
// Toggle whether the restaurant is accepting new orders
// ──────────────────────────────────────────────
export const toggleAcceptingOrders = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const { is_accepting_orders } = req.body;

    if (typeof is_accepting_orders !== 'boolean') {
      res.status(400).json({ error: 'is_accepting_orders must be a boolean.' });
      return;
    }

    // Find approved application for this user
    const { data: application, error: fetchError } = await supabase.admin
      .from('restaurant_applications')
      .select('id')
      .eq('user_id', userId)
      .eq('status', 'APPROVED')
      .maybeSingle();

    if (fetchError || !application) {
      res.status(404).json({ error: 'No approved restaurant application found.' });
      return;
    }

    const { data: updated, error: updateError } = await supabase.admin
      .from('restaurant_applications')
      .update({
        is_accepting_orders,
        updated_at: new Date().toISOString(),
      })
      .eq('id', application.id)
      .select('id, is_accepting_orders')
      .single();

    if (updateError) {
      console.error('Toggle accepting orders error:', updateError);
      res.status(500).json({ error: 'Failed to toggle accepting orders.' });
      return;
    }

    res.status(200).json({
      message: is_accepting_orders ? 'Now accepting orders.' : 'Order acceptance paused.',
      is_accepting_orders: updated.is_accepting_orders,
    });
  } catch (error) {
    console.error('Toggle accepting orders error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

